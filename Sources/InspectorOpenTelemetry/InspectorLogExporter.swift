import Foundation
import InspectorCore
import OpenTelemetryApi
import OpenTelemetrySdk

public final class InspectorLogExporter: LogRecordExporter, @unchecked Sendable {
    public let store: LogStore

    private let lifecycle = ExporterLifecycle()

    public init(store: LogStore) {
        self.store = store
    }

    public func export(
        logRecords: [ReadableLogRecord],
        explicitTimeout: TimeInterval? = nil
    ) -> ExportResult {
        let snapshots = logRecords.map(LogSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }
        Task {
            defer { lifecycle.complete() }
            await store.insert(snapshots)
        }
        return .success
    }

    public func forceFlush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
        lifecycle.wait(explicitTimeout: explicitTimeout) ? .success : .failure
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) {
        lifecycle.markShutdown()
        _ = forceFlush(explicitTimeout: explicitTimeout)
    }

    public func export(
        logRecords: [ReadableLogRecord],
        explicitTimeout: TimeInterval? = nil
    ) async -> ExportResult {
        guard !Task.isCancelled else {
            return .failure
        }
        let snapshots = logRecords.map(LogSnapshot.init)
        guard lifecycle.begin() else {
            return .failure
        }
        defer { lifecycle.complete() }
        await store.insert(snapshots)
        return .success
    }

    public func forceFlush(explicitTimeout: TimeInterval? = nil) async -> ExportResult {
        await lifecycle.wait(explicitTimeout: explicitTimeout) ? .success : .failure
    }

    public func shutdown(explicitTimeout: TimeInterval? = nil) async {
        lifecycle.markShutdown()
        _ = await forceFlush(explicitTimeout: explicitTimeout)
    }
}

public extension LogSnapshot {
    init(readableLogRecord record: ReadableLogRecord) {
        self.init(
            timestamp: TelemetryTimestamp(date: record.timestamp),
            observedTimestamp: record.observedTimestamp.map(TelemetryTimestamp.init),
            traceID: record.spanContext.map { TraceID(rawValue: $0.traceId.description) },
            spanID: record.spanContext.map { SpanID(rawValue: $0.spanId.description) },
            severity: record.severity.map {
                LogSeverity(rawValue: $0.rawValue, text: $0.description)
            },
            body: record.body.map(TelemetryAttributeValue.init),
            eventName: record.eventName,
            attributes: record.attributes.mapValues(TelemetryAttributeValue.init),
            resource: ResourceSnapshot(
                attributes: record.resource.attributes.mapValues(TelemetryAttributeValue.init)
            ),
            instrumentationScope: InstrumentationScopeSnapshot(
                name: record.instrumentationScopeInfo.name,
                version: record.instrumentationScopeInfo.version,
                schemaURL: record.instrumentationScopeInfo.schemaUrl,
                attributes: (record.instrumentationScopeInfo.attributes ?? [:])
                    .mapValues(TelemetryAttributeValue.init)
            )
        )
    }

    private init(_ record: ReadableLogRecord) {
        self.init(readableLogRecord: record)
    }
}
