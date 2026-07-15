import Foundation

public typealias AttributeRedactor = @Sendable (
    _ key: String,
    _ value: TelemetryAttributeValue
) -> TelemetryAttributeValue?

public struct TraceStoreConfiguration: Hashable, Sendable {
    public let maximumSpanCount: Int
    public let maximumEstimatedBytes: Int
    public let maximumAge: Duration
    public let maximumAttributeValueBytes: Int

    public init(
        maximumSpanCount: Int = 1_000,
        maximumEstimatedBytes: Int = 5_000_000,
        maximumAge: Duration = .seconds(3_600),
        maximumAttributeValueBytes: Int = 4_096
    ) {
        precondition(maximumSpanCount > 0, "maximumSpanCount must be greater than zero")
        precondition(maximumEstimatedBytes > 0, "maximumEstimatedBytes must be greater than zero")
        precondition(maximumAge > .zero, "maximumAge must be greater than zero")
        precondition(
            maximumAttributeValueBytes > 0,
            "maximumAttributeValueBytes must be greater than zero"
        )
        self.maximumSpanCount = maximumSpanCount
        self.maximumEstimatedBytes = maximumEstimatedBytes
        self.maximumAge = maximumAge
        self.maximumAttributeValueBytes = maximumAttributeValueBytes
    }
}

public struct TraceStoreStatistics: Equatable, Sendable {
    public let spanCount: Int
    public let traceCount: Int
    public let estimatedBytes: Int

    public init(spanCount: Int, traceCount: Int, estimatedBytes: Int) {
        self.spanCount = spanCount
        self.traceCount = traceCount
        self.estimatedBytes = estimatedBytes
    }
}

public actor TraceStore {
    public typealias Clock = @Sendable () -> TelemetryTimestamp

    private struct SpanKey: Hashable {
        let traceID: TraceID
        let spanID: SpanID
    }

    public let configuration: TraceStoreConfiguration

    private let redactor: AttributeRedactor
    private let clock: Clock
    private var spansByKey: [SpanKey: SpanSnapshot] = [:]
    private var continuations: [UUID: AsyncStream<[TraceSnapshot]>.Continuation] = [:]

    public init(
        configuration: TraceStoreConfiguration = TraceStoreConfiguration(),
        redactor: @escaping AttributeRedactor = { _, value in value },
        clock: @escaping Clock = { TelemetryTimestamp(date: Date()) }
    ) {
        self.configuration = configuration
        self.redactor = redactor
        self.clock = clock
    }

    public func insert(_ spans: [SpanSnapshot]) {
        for span in spans {
            let sanitized = sanitize(span)
            spansByKey[SpanKey(traceID: sanitized.traceID, spanID: sanitized.spanID)] = sanitized
        }
        _ = evictExpired()
        evictToLimits()
        publish()
    }

    public func removeAll() {
        spansByKey.removeAll(keepingCapacity: true)
        publish()
    }

    public func traces() -> [TraceSnapshot] {
        if evictExpired() {
            publish()
        }
        return makeTraces()
    }

    public func statistics() -> TraceStoreStatistics {
        if evictExpired() {
            publish()
        }
        return TraceStoreStatistics(
            spanCount: spansByKey.count,
            traceCount: Set(spansByKey.values.map(\.traceID)).count,
            estimatedBytes: estimatedByteCount
        )
    }

    public func changes() -> AsyncStream<[TraceSnapshot]> {
        if evictExpired() {
            publish()
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(makeTraces())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    private var estimatedByteCount: Int {
        spansByKey.values.reduce(0) { $0 + $1.estimatedByteCount }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish() {
        let traces = makeTraces()
        for continuation in continuations.values {
            continuation.yield(traces)
        }
    }

    private func makeTraces() -> [TraceSnapshot] {
        Dictionary(grouping: spansByKey.values, by: \.traceID)
            .map { TraceSnapshot(traceID: $0.key, spans: $0.value) }
            .sorted {
                let lhsEnd = $0.endTime ?? TelemetryTimestamp(nanosecondsSinceEpoch: 0)
                let rhsEnd = $1.endTime ?? TelemetryTimestamp(nanosecondsSinceEpoch: 0)
                if lhsEnd != rhsEnd {
                    return lhsEnd > rhsEnd
                }
                return $0.traceID < $1.traceID
            }
    }

    @discardableResult
    private func evictExpired() -> Bool {
        let previousCount = spansByKey.count
        let now = clock().nanosecondsSinceEpoch
        let age = configuration.maximumAge.nanosecondsClamped
        let cutoff = now > age ? now - age : 0
        spansByKey = spansByKey.filter { $0.value.endTime.nanosecondsSinceEpoch >= cutoff }
        return spansByKey.count != previousCount
    }

    private func evictToLimits() {
        while
            spansByKey.count > configuration.maximumSpanCount
                || estimatedByteCount > configuration.maximumEstimatedBytes
        {
            guard let oldest = spansByKey.min(by: { evictionOrdering($0.value, $1.value) }) else {
                return
            }
            spansByKey.removeValue(forKey: oldest.key)
        }
    }

    private func evictionOrdering(_ lhs: SpanSnapshot, _ rhs: SpanSnapshot) -> Bool {
        if lhs.endTime != rhs.endTime {
            return lhs.endTime < rhs.endTime
        }
        if lhs.traceID != rhs.traceID {
            return lhs.traceID < rhs.traceID
        }
        return lhs.spanID < rhs.spanID
    }

    private func sanitize(_ span: SpanSnapshot) -> SpanSnapshot {
        SpanSnapshot(
            traceID: span.traceID,
            spanID: span.spanID,
            parentSpanID: span.parentSpanID,
            traceState: span.traceState,
            name: span.name,
            kind: span.kind,
            startTime: span.startTime,
            endTime: span.endTime,
            attributes: sanitize(span.attributes),
            events: span.events.map {
                SpanEventSnapshot(
                    id: $0.id,
                    name: $0.name,
                    timestamp: $0.timestamp,
                    attributes: sanitize($0.attributes),
                    droppedAttributeCount: $0.droppedAttributeCount
                )
            },
            links: span.links.map {
                SpanLinkSnapshot(
                    id: $0.id,
                    traceID: $0.traceID,
                    spanID: $0.spanID,
                    traceState: $0.traceState,
                    attributes: sanitize($0.attributes),
                    droppedAttributeCount: $0.droppedAttributeCount
                )
            },
            status: span.status,
            resource: ResourceSnapshot(
                attributes: sanitize(span.resource.attributes),
                schemaURL: span.resource.schemaURL
            ),
            instrumentationScope: InstrumentationScopeSnapshot(
                name: span.instrumentationScope.name,
                version: span.instrumentationScope.version,
                schemaURL: span.instrumentationScope.schemaURL,
                attributes: sanitize(span.instrumentationScope.attributes)
            ),
            droppedAttributeCount: span.droppedAttributeCount,
            droppedEventCount: span.droppedEventCount,
            droppedLinkCount: span.droppedLinkCount
        )
    }

    private func sanitize(
        _ attributes: [String: TelemetryAttributeValue]
    ) -> [String: TelemetryAttributeValue] {
        attributes.reduce(into: [:]) { result, entry in
            guard let redacted = redactor(entry.key, entry.value) else {
                return
            }
            result[entry.key] = truncate(redacted)
        }
    }

    private func truncate(_ value: TelemetryAttributeValue) -> TelemetryAttributeValue {
        switch value {
        case let .string(value):
            return .string(value.truncatedUTF8(to: configuration.maximumAttributeValueBytes))
        case let .array(values):
            return .array(values.map(truncate))
        case let .dictionary(values):
            return .dictionary(values.mapValues(truncate))
        case let .bytes(value):
            return .bytes(Data(value.prefix(configuration.maximumAttributeValueBytes)))
        case .bool, .int, .double:
            return value
        }
    }
}

private extension Duration {
    var nanosecondsClamped: UInt64 {
        let components = self.components
        guard components.seconds >= 0 else {
            return 0
        }
        let seconds = UInt64(components.seconds)
        let nanoseconds = UInt64(max(0, components.attoseconds / 1_000_000_000))
        let (scaledSeconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow else {
            return .max
        }
        let (total, additionOverflow) = scaledSeconds.addingReportingOverflow(nanoseconds)
        return additionOverflow ? .max : total
    }
}

private extension String {
    func truncatedUTF8(to maximumBytes: Int) -> String {
        guard utf8.count > maximumBytes else {
            return self
        }

        var end = utf8.index(utf8.startIndex, offsetBy: maximumBytes)
        while end > utf8.startIndex {
            if let result = String(bytes: utf8[..<end], encoding: .utf8) {
                return result
            }
            end = utf8.index(before: end)
        }
        return ""
    }
}
