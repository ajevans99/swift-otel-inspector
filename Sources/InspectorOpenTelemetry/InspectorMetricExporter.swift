import Foundation
import InspectorCore
import OpenTelemetryApi
import OpenTelemetrySdk

public final class InspectorMetricExporter: MetricExporter, @unchecked Sendable {
    public let store: MetricStore

    private let lifecycle = ExporterLifecycle()

    public init(store: MetricStore) {
        self.store = store
    }

    public func getAggregationTemporality(
        for instrument: InstrumentType
    ) -> AggregationTemporality {
        .cumulative
    }

    public func export(metrics: [MetricData]) -> ExportResult {
        let snapshots = metrics.map(MetricSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }
        defer { lifecycle.complete() }
        let completion = DispatchSemaphore(value: 0)
        Task {
            await store.insert(snapshots)
            completion.signal()
        }
        completion.wait()
        return .success
    }

    public func flush() -> ExportResult {
        lifecycle.wait(explicitTimeout: nil) ? .success : .failure
    }

    public func shutdown() -> ExportResult {
        lifecycle.markShutdown()
        return flush()
    }

    public func export(metrics: [MetricData]) async -> ExportResult {
        guard !Task.isCancelled else {
            return .failure
        }
        let snapshots = metrics.map(MetricSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }
        defer { lifecycle.complete() }
        await store.insert(snapshots)
        return .success
    }

    public func flush() async -> ExportResult {
        await lifecycle.wait(explicitTimeout: nil) ? .success : .failure
    }

    public func shutdown() async -> ExportResult {
        lifecycle.markShutdown()
        return await flush()
    }
}

public extension MetricSnapshot {
    init(metricData: MetricData) {
        let groupedPoints = Dictionary(grouping: metricData.data.points) {
            MetricSeriesSnapshot(
                attributes: $0.attributes.mapValues(TelemetryAttributeValue.init),
                points: []
            ).id
        }
        let series = groupedPoints.values.compactMap { points -> MetricSeriesSnapshot? in
            guard let first = points.first else {
                return nil
            }
            let attributes = first.attributes.mapValues(TelemetryAttributeValue.init)
            return MetricSeriesSnapshot(
                attributes: attributes,
                points: points.compactMap(MetricPointSnapshot.init)
            )
        }
        self.init(
            name: metricData.name,
            description: metricData.description,
            unit: metricData.unit,
            kind: MetricKind(metricData),
            temporality: MetricAggregationTemporality(metricData.data.aggregationTemporality),
            resource: ResourceSnapshot(
                attributes: metricData.resource.attributes.mapValues(TelemetryAttributeValue.init)
            ),
            instrumentationScope: InstrumentationScopeSnapshot(
                name: metricData.instrumentationScopeInfo.name,
                version: metricData.instrumentationScopeInfo.version,
                schemaURL: metricData.instrumentationScopeInfo.schemaUrl,
                attributes: (metricData.instrumentationScopeInfo.attributes ?? [:])
                    .mapValues(TelemetryAttributeValue.init)
            ),
            series: series
        )
    }

    private init(_ metricData: MetricData) {
        self.init(metricData: metricData)
    }
}

private extension MetricKind {
    init(_ metricData: MetricData) {
        switch metricData.type {
        case .LongGauge, .DoubleGauge:
            self = .gauge
        case .LongSum, .DoubleSum:
            self = .sum(monotonic: metricData.isMonotonic)
        case .Summary:
            self = .summary
        case .Histogram:
            self = .histogram
        case .ExponentialHistogram:
            self = .exponentialHistogram
        }
    }
}

private extension MetricAggregationTemporality {
    init(_ temporality: AggregationTemporality) {
        switch temporality {
        case .cumulative:
            self = .cumulative
        case .delta:
            self = .delta
        }
    }
}

private extension MetricPointSnapshot {
    init?(_ point: PointData) {
        let value: MetricPointValue
        switch point {
        case let point as LongPointData:
            value = .number(.integer(Int64(point.value)))
        case let point as DoublePointData:
            value = .number(.double(point.value))
        case let point as HistogramPointData:
            value = .histogram(
                MetricHistogramSnapshot(
                    count: point.count,
                    sum: point.sum,
                    minimum: point.hasMin ? point.min : nil,
                    maximum: point.hasMax ? point.max : nil,
                    boundaries: point.boundaries,
                    bucketCounts: point.counts.map { UInt64(max(0, $0)) }
                )
            )
        case let point as ExponentialHistogramPointData:
            value = .exponentialHistogram(
                MetricExponentialHistogramSnapshot(
                    count: UInt64(max(0, point.count)),
                    sum: point.sum,
                    minimum: point.hasMin ? point.min : nil,
                    maximum: point.hasMax ? point.max : nil,
                    scale: point.scale,
                    zeroCount: UInt64(max(0, point.zeroCount)),
                    positive: MetricExponentialBucketsSnapshot(
                        offset: point.positiveBuckets.offset,
                        bucketCounts: point.positiveBuckets.bucketCounts.map {
                            UInt64(max(0, $0))
                        }
                    ),
                    negative: MetricExponentialBucketsSnapshot(
                        offset: point.negativeBuckets.offset,
                        bucketCounts: point.negativeBuckets.bucketCounts.map {
                            UInt64(max(0, $0))
                        }
                    )
                )
            )
        case let point as SummaryPointData:
            value = .summary(
                MetricSummarySnapshot(
                    count: point.count,
                    sum: point.sum,
                    quantiles: point.values.map {
                        MetricQuantileSnapshot(quantile: $0.quantile, value: $0.value)
                    }
                )
            )
        default:
            return nil
        }
        self.init(
            startTime: TelemetryTimestamp(nanosecondsSinceEpoch: point.startEpochNanos),
            endTime: TelemetryTimestamp(nanosecondsSinceEpoch: point.endEpochNanos),
            value: value,
            exemplars: point.exemplars.compactMap(MetricExemplarSnapshot.init)
        )
    }
}

private extension MetricExemplarSnapshot {
    init?(_ exemplar: ExemplarData) {
        let value: MetricNumber
        switch exemplar {
        case let exemplar as LongExemplarData:
            value = .integer(Int64(exemplar.value))
        case let exemplar as DoubleExemplarData:
            value = .double(exemplar.value)
        default:
            return nil
        }
        self.init(
            timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: exemplar.epochNanos),
            value: value,
            filteredAttributes: exemplar.filteredAttributes
                .mapValues(TelemetryAttributeValue.init),
            traceID: exemplar.spanContext.map {
                TraceID(rawValue: $0.traceId.description)
            },
            spanID: exemplar.spanContext.map {
                SpanID(rawValue: $0.spanId.description)
            }
        )
    }
}
