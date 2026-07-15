import Foundation

public struct MetricStoreConfiguration: Hashable, Sendable {
    public let maximumMetricCount: Int
    public let maximumSeriesCount: Int
    public let maximumSeriesPerMetric: Int
    public let maximumPointsPerSeries: Int
    public let maximumEstimatedBytes: Int
    public let maximumAge: Duration
    public let maximumAttributeValueBytes: Int

    public init(
        maximumMetricCount: Int = 200,
        maximumSeriesCount: Int = 1_000,
        maximumSeriesPerMetric: Int = 50,
        maximumPointsPerSeries: Int = 120,
        maximumEstimatedBytes: Int = 5_000_000,
        maximumAge: Duration = .seconds(3_600),
        maximumAttributeValueBytes: Int = 4_096
    ) {
        precondition(maximumMetricCount > 0)
        precondition(maximumSeriesCount > 0)
        precondition(maximumSeriesPerMetric > 0)
        precondition(maximumPointsPerSeries > 0)
        precondition(maximumEstimatedBytes > 0)
        precondition(maximumAge > .zero)
        precondition(maximumAttributeValueBytes > 0)
        self.maximumMetricCount = maximumMetricCount
        self.maximumSeriesCount = maximumSeriesCount
        self.maximumSeriesPerMetric = maximumSeriesPerMetric
        self.maximumPointsPerSeries = maximumPointsPerSeries
        self.maximumEstimatedBytes = maximumEstimatedBytes
        self.maximumAge = maximumAge
        self.maximumAttributeValueBytes = maximumAttributeValueBytes
    }
}

public struct MetricStoreStatistics: Equatable, Sendable {
    public let metricCount: Int
    public let seriesCount: Int
    public let pointCount: Int
    public let estimatedBytes: Int

    public init(metricCount: Int, seriesCount: Int, pointCount: Int, estimatedBytes: Int) {
        self.metricCount = metricCount
        self.seriesCount = seriesCount
        self.pointCount = pointCount
        self.estimatedBytes = estimatedBytes
    }
}

public actor MetricStore {
    public typealias Clock = @Sendable () -> TelemetryTimestamp

    public let configuration: MetricStoreConfiguration

    private let redactor: AttributeRedactor
    private let clock: Clock
    private var metricsByID: [MetricID: MetricSnapshot] = [:]
    private var continuations: [UUID: AsyncStream<[MetricSnapshot]>.Continuation] = [:]
    private var expirationTask: Task<Void, Never>?
    private var expirationGeneration: UInt64 = 0

    public init(
        configuration: MetricStoreConfiguration = MetricStoreConfiguration(),
        redactor: @escaping AttributeRedactor = { _, value in value },
        clock: @escaping Clock = { TelemetryTimestamp(date: Date()) }
    ) {
        self.configuration = configuration
        self.redactor = redactor
        self.clock = clock
    }

    public func insert(_ metrics: [MetricSnapshot]) {
        for metric in metrics {
            merge(sanitize(metric))
        }
        enforceLimits()
        scheduleExpiration()
        publish()
    }

    public func removeAll() {
        expirationGeneration &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        metricsByID.removeAll(keepingCapacity: true)
        publish()
    }

    public func metrics() -> [MetricSnapshot] {
        if evictExpired() {
            publish()
        }
        return orderedMetrics()
    }

    public func metric(id: MetricID) -> MetricSnapshot? {
        if evictExpired() {
            publish()
        }
        return metricsByID[id]
    }

    public func statistics() -> MetricStoreStatistics {
        if evictExpired() {
            publish()
        }
        return currentStatistics
    }

    public func changes() -> AsyncStream<[MetricSnapshot]> {
        if evictExpired() {
            publish()
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(orderedMetrics())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    private func merge(_ incoming: MetricSnapshot) {
        guard let existing = metricsByID[incoming.id] else {
            metricsByID[incoming.id] = normalized(incoming)
            return
        }
        var seriesByID = Dictionary(uniqueKeysWithValues: existing.series.map { ($0.id, $0) })
        for series in incoming.series {
            guard let previous = seriesByID[series.id] else {
                seriesByID[series.id] = normalized(series)
                continue
            }
            var pointsByWindow = Dictionary(
                uniqueKeysWithValues: previous.points.map { (PointWindow($0), $0) }
            )
            for point in series.points {
                pointsByWindow[PointWindow(point)] = point
            }
            seriesByID[series.id] = MetricSeriesSnapshot(
                id: series.id,
                attributes: series.attributes,
                points: Array(pointsByWindow.values)
            )
        }
        metricsByID[incoming.id] = normalized(
            MetricSnapshot(
                id: incoming.id,
                name: incoming.name,
                description: incoming.description,
                unit: incoming.unit,
                kind: incoming.kind,
                temporality: incoming.temporality,
                resource: incoming.resource,
                instrumentationScope: incoming.instrumentationScope,
                series: Array(seriesByID.values)
            )
        )
    }

    private func normalized(_ metric: MetricSnapshot) -> MetricSnapshot {
        let groupedSeries = Dictionary(grouping: metric.series, by: \.id)
        let series = groupedSeries.values
            .map { duplicates in
                let template = duplicates[0]
                var pointsByWindow: [PointWindow: MetricPointSnapshot] = [:]
                duplicates.flatMap(\.points).forEach {
                    pointsByWindow[PointWindow($0)] = $0
                }
                return normalized(
                    MetricSeriesSnapshot(
                        id: template.id,
                        attributes: template.attributes,
                        points: Array(pointsByWindow.values)
                    )
                )
            }
            .filter { !$0.points.isEmpty }
            .sorted { $0.id < $1.id }
        return MetricSnapshot(
            id: metric.id,
            name: metric.name,
            description: metric.description,
            unit: metric.unit,
            kind: metric.kind,
            temporality: metric.temporality,
            resource: metric.resource,
            instrumentationScope: metric.instrumentationScope,
            series: series
        )
    }

    private func normalized(_ series: MetricSeriesSnapshot) -> MetricSeriesSnapshot {
        let points = series.points.sorted(by: pointOrdering)
        let limited = points.suffix(configuration.maximumPointsPerSeries)
        return MetricSeriesSnapshot(
            id: series.id,
            attributes: series.attributes,
            points: Array(limited)
        )
    }

    private func sanitize(_ metric: MetricSnapshot) -> MetricSnapshot {
        let resource = ResourceSnapshot(
            attributes: sanitize(metric.resource.attributes),
            schemaURL: metric.resource.schemaURL
        )
        let scope = InstrumentationScopeSnapshot(
            name: metric.instrumentationScope.name,
            version: metric.instrumentationScope.version,
            schemaURL: metric.instrumentationScope.schemaURL,
            attributes: sanitize(metric.instrumentationScope.attributes)
        )
        let series = metric.series.map {
            MetricSeriesSnapshot(
                attributes: sanitize($0.attributes),
                points: $0.points.map(sanitize)
            )
        }
        return MetricSnapshot(
            name: metric.name,
            description: metric.description,
            unit: metric.unit,
            kind: metric.kind,
            temporality: metric.temporality,
            resource: resource,
            instrumentationScope: scope,
            series: series
        )
    }

    private func sanitize(_ point: MetricPointSnapshot) -> MetricPointSnapshot {
        MetricPointSnapshot(
            startTime: point.startTime,
            endTime: point.endTime,
            value: point.value,
            exemplars: point.exemplars.map {
                MetricExemplarSnapshot(
                    timestamp: $0.timestamp,
                    value: $0.value,
                    filteredAttributes: sanitize($0.filteredAttributes),
                    traceID: $0.traceID,
                    spanID: $0.spanID
                )
            }
        )
    }

    private func sanitize(
        _ attributes: [String: TelemetryAttributeValue]
    ) -> [String: TelemetryAttributeValue] {
        attributes.reduce(into: [:]) { result, entry in
            guard let redacted = redactor(entry.key, entry.value) else {
                return
            }
            result[entry.key] = redacted.truncated(to: configuration.maximumAttributeValueBytes)
        }
    }

    private func enforceLimits() {
        _ = evictExpired()
        enforcePerMetricSeriesLimit()
        enforceGlobalSeriesLimit()
        enforceMetricLimit()
        enforceByteLimit()
        removeEmptyMetrics()
    }

    private func enforcePerMetricSeriesLimit() {
        for metric in metricsByID.values where metric.series.count > configuration.maximumSeriesPerMetric {
            let retained = metric.series
                .sorted(by: newestSeriesFirst)
                .prefix(configuration.maximumSeriesPerMetric)
            replaceSeries(in: metric, with: Array(retained))
        }
    }

    private func enforceGlobalSeriesLimit() {
        while currentStatistics.seriesCount > configuration.maximumSeriesCount {
            guard let oldest = oldestSeries else {
                return
            }
            removeSeries(metricID: oldest.metricID, seriesID: oldest.seriesID)
        }
    }

    private func enforceMetricLimit() {
        while metricsByID.count > configuration.maximumMetricCount {
            guard let oldest = metricsByID.values.min(by: metricEvictionOrdering) else {
                return
            }
            metricsByID.removeValue(forKey: oldest.id)
        }
    }

    private func enforceByteLimit() {
        while currentStatistics.estimatedBytes > configuration.maximumEstimatedBytes {
            guard let oldest = oldestPoint else {
                return
            }
            removePoint(
                metricID: oldest.metricID,
                seriesID: oldest.seriesID,
                window: oldest.window
            )
        }
    }

    @discardableResult
    private func evictExpired() -> Bool {
        let previousPointCount = currentStatistics.pointCount
        let now = clock().nanosecondsSinceEpoch
        let age = configuration.maximumAge.nanosecondsClamped
        let cutoff = now > age ? now - age : 0
        for metric in metricsByID.values {
            let series = metric.series.compactMap { series -> MetricSeriesSnapshot? in
                let points = series.points.filter {
                    $0.endTime.nanosecondsSinceEpoch >= cutoff
                }
                guard !points.isEmpty else {
                    return nil
                }
                return MetricSeriesSnapshot(
                    id: series.id,
                    attributes: series.attributes,
                    points: points
                )
            }
            replaceSeries(in: metric, with: series)
        }
        removeEmptyMetrics()
        return currentStatistics.pointCount != previousPointCount
    }

    private func scheduleExpiration() {
        expirationGeneration &+= 1
        let generation = expirationGeneration
        expirationTask?.cancel()
        expirationTask = nil
        guard let oldest = oldestPoint?.window.end else {
            return
        }
        let now = clock().nanosecondsSinceEpoch
        let age = configuration.maximumAge.nanosecondsClamped
        let expiration = oldest.addingReportingOverflow(age)
        let firstExpired = expiration.partialValue.addingReportingOverflow(1)
        let expirationTime = expiration.overflow || firstExpired.overflow
            ? UInt64.max
            : firstExpired.partialValue
        let delay = expirationTime > now ? expirationTime - now : 1
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(Int64(clamping: delay)))
            guard !Task.isCancelled else {
                return
            }
            await self?.expireAndReschedule(generation: generation)
        }
    }

    private func expireAndReschedule(generation: UInt64) {
        guard generation == expirationGeneration else {
            return
        }
        expirationTask = nil
        if evictExpired() {
            publish()
        }
        scheduleExpiration()
    }

    private var currentStatistics: MetricStoreStatistics {
        let metrics = Array(metricsByID.values)
        return MetricStoreStatistics(
            metricCount: metrics.count,
            seriesCount: metrics.reduce(0) { $0 + $1.series.count },
            pointCount: metrics.reduce(0) { count, metric in
                count + metric.series.reduce(0) { $0 + $1.points.count }
            },
            estimatedBytes: metrics.reduce(0) { $0 + $1.estimatedByteCount }
        )
    }

    private var oldestSeries: (metricID: MetricID, seriesID: MetricSeriesID)? {
        metricsByID.values.flatMap { metric in
            metric.series.map { (metric.id, $0) }
        }.min {
            if latestTime($0.1) != latestTime($1.1) {
                return latestTime($0.1) < latestTime($1.1)
            }
            if $0.0 != $1.0 {
                return $0.0 < $1.0
            }
            return $0.1.id < $1.1.id
        }.map { ($0.0, $0.1.id) }
    }

    private var oldestPoint: (
        metricID: MetricID,
        seriesID: MetricSeriesID,
        window: PointWindow
    )? {
        metricsByID.values.flatMap { metric in
            metric.series.flatMap { series in
                series.points.map { (metric.id, series.id, PointWindow($0)) }
            }
        }.min {
            if $0.2.end != $1.2.end {
                return $0.2.end < $1.2.end
            }
            if $0.0 != $1.0 {
                return $0.0 < $1.0
            }
            return $0.1 < $1.1
        }
    }

    private func replaceSeries(in metric: MetricSnapshot, with series: [MetricSeriesSnapshot]) {
        metricsByID[metric.id] = MetricSnapshot(
            id: metric.id,
            name: metric.name,
            description: metric.description,
            unit: metric.unit,
            kind: metric.kind,
            temporality: metric.temporality,
            resource: metric.resource,
            instrumentationScope: metric.instrumentationScope,
            series: series.sorted { $0.id < $1.id }
        )
    }

    private func removeSeries(metricID: MetricID, seriesID: MetricSeriesID) {
        guard let metric = metricsByID[metricID] else {
            return
        }
        replaceSeries(in: metric, with: metric.series.filter { $0.id != seriesID })
        removeEmptyMetrics()
    }

    private func removePoint(
        metricID: MetricID,
        seriesID: MetricSeriesID,
        window: PointWindow
    ) {
        guard let metric = metricsByID[metricID] else {
            return
        }
        let series = metric.series.compactMap { series -> MetricSeriesSnapshot? in
            guard series.id == seriesID else {
                return series
            }
            let points = series.points.filter { PointWindow($0) != window }
            return points.isEmpty
                ? nil
                : MetricSeriesSnapshot(
                    id: series.id,
                    attributes: series.attributes,
                    points: points
                )
        }
        replaceSeries(in: metric, with: series)
        removeEmptyMetrics()
    }

    private func removeEmptyMetrics() {
        metricsByID = metricsByID.filter { !$0.value.series.isEmpty }
    }

    private func orderedMetrics() -> [MetricSnapshot] {
        metricsByID.values.sorted {
            let lhs = $0.latestTimestamp?.nanosecondsSinceEpoch ?? 0
            let rhs = $1.latestTimestamp?.nanosecondsSinceEpoch ?? 0
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }

    private func publish() {
        let metrics = orderedMetrics()
        continuations.values.forEach { $0.yield(metrics) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func newestSeriesFirst(
        _ lhs: MetricSeriesSnapshot,
        _ rhs: MetricSeriesSnapshot
    ) -> Bool {
        let lhsTime = latestTime(lhs)
        let rhsTime = latestTime(rhs)
        return lhsTime == rhsTime ? lhs.id < rhs.id : lhsTime > rhsTime
    }

    private func latestTime(_ series: MetricSeriesSnapshot) -> UInt64 {
        series.points.last?.endTime.nanosecondsSinceEpoch ?? 0
    }

    private func metricEvictionOrdering(_ lhs: MetricSnapshot, _ rhs: MetricSnapshot) -> Bool {
        let lhsTime = lhs.latestTimestamp?.nanosecondsSinceEpoch ?? 0
        let rhsTime = rhs.latestTimestamp?.nanosecondsSinceEpoch ?? 0
        return lhsTime == rhsTime ? lhs.id < rhs.id : lhsTime < rhsTime
    }

    private func pointOrdering(_ lhs: MetricPointSnapshot, _ rhs: MetricPointSnapshot) -> Bool {
        if lhs.endTime != rhs.endTime {
            return lhs.endTime < rhs.endTime
        }
        return lhs.startTime < rhs.startTime
    }
}

private struct PointWindow: Hashable {
    let start: UInt64
    let end: UInt64

    init(_ point: MetricPointSnapshot) {
        start = point.startTime.nanosecondsSinceEpoch
        end = point.endTime.nanosecondsSinceEpoch
    }
}

private extension MetricSnapshot {
    var estimatedByteCount: Int {
        var byteCount = 256
        byteCount += id.rawValue.utf8.count
        byteCount += name.utf8.count
        byteCount += description.utf8.count
        byteCount += unit.utf8.count
        byteCount += resource.schemaURL?.utf8.count ?? 0
        byteCount += resource.attributes.estimatedByteCount
        byteCount += instrumentationScope.name.utf8.count
        byteCount += instrumentationScope.version?.utf8.count ?? 0
        byteCount += instrumentationScope.schemaURL?.utf8.count ?? 0
        byteCount += instrumentationScope.attributes.estimatedByteCount
        byteCount += series.reduce(0) { $0 + $1.estimatedByteCount }
        return byteCount
    }
}

private extension MetricSeriesSnapshot {
    var estimatedByteCount: Int {
        96 + id.rawValue.utf8.count + attributes.estimatedByteCount
            + points.reduce(0) { $0 + $1.estimatedByteCount }
    }
}

private extension MetricPointSnapshot {
    var estimatedByteCount: Int {
        96 + value.estimatedByteCount + exemplars.reduce(0) {
            $0 + 80 + $1.filteredAttributes.estimatedByteCount
        }
    }
}

private extension MetricPointValue {
    var estimatedByteCount: Int {
        switch self {
        case .number:
            16
        case let .histogram(value):
            64 + value.boundaries.count * 8 + value.bucketCounts.count * 8
        case let .exponentialHistogram(value):
            80 + value.positive.bucketCounts.count * 8 + value.negative.bucketCounts.count * 8
        case let .summary(value):
            32 + value.quantiles.count * 16
        }
    }
}
