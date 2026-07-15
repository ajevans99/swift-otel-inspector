import Foundation
import InspectorCore
import OpenTelemetryApi
import OpenTelemetrySdk

public final class InspectorSpanExporter: SpanExporter, @unchecked Sendable {
    public let store: TraceStore

    private let lifecycle = ExporterLifecycle()

    public init(store: TraceStore) {
        self.store = store
    }

    @discardableResult
    public func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval? = nil
    ) -> SpanExporterResultCode {
        let snapshots = spans.map(SpanSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }

        Task {
            defer { lifecycle.complete() }
            await store.insert(snapshots)
        }
        return .success
    }

    public func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
        lifecycle.wait(explicitTimeout: explicitTimeout) ? .success : .failure
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) {
        lifecycle.markShutdown()
        _ = flush(explicitTimeout: explicitTimeout)
    }

    @discardableResult
    public func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval? = nil
    ) async -> SpanExporterResultCode {
        guard !Task.isCancelled else {
            return .failure
        }
        let snapshots = spans.map(SpanSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }

        defer { lifecycle.complete() }
        await store.insert(snapshots)
        return .success
    }

    public func flush(explicitTimeout: TimeInterval? = nil) async -> SpanExporterResultCode {
        await lifecycle.wait(explicitTimeout: explicitTimeout) ? .success : .failure
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) async {
        lifecycle.markShutdown()
        _ = await flush(explicitTimeout: explicitTimeout)
    }
}

public extension SpanSnapshot {
    init(spanData: SpanData) {
        self.init(
            traceID: TraceID(rawValue: spanData.traceId.description),
            spanID: SpanID(rawValue: spanData.spanId.description),
            parentSpanID: spanData.parentSpanId.map { SpanID(rawValue: $0.description) },
            traceState: spanData.traceState.entries.isEmpty
                ? nil
                : spanData.traceState.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
            name: spanData.name,
            kind: InspectorSpanKind(spanData.kind),
            startTime: TelemetryTimestamp(date: spanData.startTime),
            endTime: TelemetryTimestamp(date: spanData.endTime),
            attributes: spanData.attributes.mapValues(TelemetryAttributeValue.init),
            events: spanData.events.map(SpanEventSnapshot.init),
            links: spanData.links.map(SpanLinkSnapshot.init),
            status: InspectorSpanStatus(spanData.status),
            resource: ResourceSnapshot(
                attributes: spanData.resource.attributes.mapValues(TelemetryAttributeValue.init)
            ),
            instrumentationScope: InstrumentationScopeSnapshot(
                name: spanData.instrumentationScope.name,
                version: spanData.instrumentationScope.version,
                schemaURL: spanData.instrumentationScope.schemaUrl,
                attributes: (spanData.instrumentationScope.attributes ?? [:])
                    .mapValues(TelemetryAttributeValue.init)
            ),
            droppedAttributeCount: max(0, spanData.totalAttributeCount - spanData.attributes.count),
            droppedEventCount: max(0, spanData.totalRecordedEvents - spanData.events.count),
            droppedLinkCount: max(0, spanData.totalRecordedLinks - spanData.links.count)
        )
    }

    private init(_ spanData: SpanData) {
        self.init(spanData: spanData)
    }
}

extension TelemetryAttributeValue {
    init(_ value: AttributeValue) {
        switch value {
        case let .string(value):
            self = .string(value)
        case let .bool(value):
            self = .bool(value)
        case let .int(value):
            self = .int(Int64(value))
        case let .double(value):
            self = .double(value)
        case let .array(value):
            self = .array(value.values.map(Self.init))
        case let .set(value):
            self = .dictionary(value.labels.mapValues(Self.init))
        case let .stringArray(value):
            self = .array(value.map { .string($0) })
        case let .boolArray(value):
            self = .array(value.map { .bool($0) })
        case let .intArray(value):
            self = .array(value.map { .int(Int64($0)) })
        case let .doubleArray(value):
            self = .array(value.map { .double($0) })
        }
    }
}

private extension InspectorSpanKind {
    init(_ kind: SpanKind) {
        switch kind {
        case .internal:
            self = .internal
        case .server:
            self = .server
        case .client:
            self = .client
        case .producer:
            self = .producer
        case .consumer:
            self = .consumer
        }
    }
}

private extension InspectorSpanStatus {
    init(_ status: Status) {
        switch status {
        case .unset:
            self = .unset
        case .ok:
            self = .ok
        case let .error(description):
            self = .error(message: description.isEmpty ? nil : description)
        }
    }
}

private extension SpanEventSnapshot {
    init(_ event: SpanData.Event) {
        self.init(
            name: event.name,
            timestamp: TelemetryTimestamp(date: event.timestamp),
            attributes: event.attributes.mapValues(TelemetryAttributeValue.init)
        )
    }
}

private extension SpanLinkSnapshot {
    init(_ link: SpanData.Link) {
        self.init(
            traceID: TraceID(rawValue: link.context.traceId.description),
            spanID: SpanID(rawValue: link.context.spanId.description),
            traceState: link.context.traceState.entries.isEmpty
                ? nil
                : link.context.traceState.entries
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ","),
            attributes: link.attributes.mapValues(TelemetryAttributeValue.init)
        )
    }
}
