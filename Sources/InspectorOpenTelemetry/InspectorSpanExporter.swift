import Foundation
import InspectorCore
import OpenTelemetryApi
import OpenTelemetrySdk

public final class InspectorSpanExporter: SpanExporter, @unchecked Sendable {
    public let store: TraceStore

    private let lock = NSLock()
    private let pendingExports = DispatchGroup()
    private var isShutdown = false

    public init(store: TraceStore) {
        self.store = store
    }

    @discardableResult
    public func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval? = nil
    ) -> SpanExporterResultCode {
        let snapshots = spans.map(SpanSnapshot.init)
        guard beginExport() else {
            return .failure
        }

        Task {
            await store.insert(snapshots)
            pendingExports.leave()
        }
        return .success
    }

    public func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
        waitForPending(explicitTimeout: explicitTimeout)
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) {
        lock.withLock {
            isShutdown = true
        }
        _ = flush(explicitTimeout: explicitTimeout)
    }

    @discardableResult
    public func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval? = nil
    ) async -> SpanExporterResultCode {
        let snapshots = spans.map(SpanSnapshot.init)
        guard beginExport() else {
            return .failure
        }

        await store.insert(snapshots)
        pendingExports.leave()
        return .success
    }

    public func flush(explicitTimeout: TimeInterval? = nil) async -> SpanExporterResultCode {
        await withCheckedContinuation { continuation in
            let waiter = FlushWaiter(continuation: continuation)
            pendingExports.notify(queue: .global()) {
                waiter.resume(returning: .success)
            }
            if let explicitTimeout {
                DispatchQueue.global().asyncAfter(deadline: deadline(for: explicitTimeout)) {
                    waiter.resume(returning: .failure)
                }
            }
        }
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) async {
        lock.withLock {
            isShutdown = true
        }
        _ = await flush(explicitTimeout: explicitTimeout)
    }

    private func beginExport() -> Bool {
        lock.withLock {
            guard !isShutdown else {
                return false
            }
            pendingExports.enter()
            return true
        }
    }

    private func waitForPending(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        let result = pendingExports.wait(timeout: deadline(for: explicitTimeout))
        return result == .success ? .success : .failure
    }

    private func deadline(for timeout: TimeInterval?) -> DispatchTime {
        guard let timeout else {
            return .distantFuture
        }
        return .now() + max(0, timeout)
    }
}

private final class FlushWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SpanExporterResultCode, Never>?

    init(continuation: CheckedContinuation<SpanExporterResultCode, Never>) {
        self.continuation = continuation
    }

    func resume(returning result: SpanExporterResultCode) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: result)
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

private extension TelemetryAttributeValue {
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
