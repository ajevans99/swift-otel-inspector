import Foundation
import InspectorCore
import InspectorOpenTelemetry
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing

@Test
func sdkCorrelatedLogIsStored() async throws {
    let logStore = LogStore()
    let exporter = InspectorLogExporter(store: logStore)
    let loggerProvider = LoggerProviderSdk(
        resource: Resource(attributes: ["service.name": .string("test-service")]),
        logRecordProcessors: [SimpleLogRecordProcessor(logRecordExporter: exporter)]
    )
    let tracerProvider = TracerProviderSdk()
    let span = tracerProvider
        .get(instrumentationName: "InspectorLogExporterTests")
        .spanBuilder(spanName: "request")
        .startSpan()
    let logger = loggerProvider.get(instrumentationScopeName: "test-logger")

    logger.logRecordBuilder()
        .setTimestamp(Date())
        .setSpanContext(span.context)
        .setSeverity(.warn)
        .setBody(.string("retry scheduled"))
        .setAttributes(["retry.attempt": .int(2)])
        .emit()

    #expect(await exporter.forceFlush(explicitTimeout: 1) == .success)
    let log = try #require(await logStore.logs().first)
    #expect(log.traceID == TraceID(rawValue: span.context.traceId.description))
    #expect(log.spanID == SpanID(rawValue: span.context.spanId.description))
    #expect(log.severity?.text == "WARN")
    #expect(log.message == "retry scheduled")
    #expect(log.attributes["retry.attempt"] == .int(2))
    #expect(log.resource.serviceName == "test-service")
}

@Test
func logExporterShutdownAndCancellationAreExplicit() async {
    let exporter = InspectorLogExporter(store: LogStore())
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await exporter.export(logRecords: [], explicitTimeout: 1)
    }
    #expect(await cancelled.value == .failure)

    await exporter.shutdown(explicitTimeout: 1)
    #expect(await exporter.export(logRecords: [], explicitTimeout: 1) == .failure)
}

@Test
func multiLogExporterReportsFailureWithoutSkippingInspector() async {
    let store = LogStore()
    let inspector = InspectorLogExporter(store: store)
    let multi = MultiLogRecordExporter(
        logRecordExporters: [FailingLogExporter(), inspector]
    )

    let result = await multi.export(logRecords: [], explicitTimeout: 1)

    #expect(result == .failure)
    #expect(await inspector.forceFlush(explicitTimeout: 1) == .success)
}

private final class FailingLogExporter: LogRecordExporter, @unchecked Sendable {
    func export(
        logRecords: [ReadableLogRecord],
        explicitTimeout: TimeInterval?
    ) -> ExportResult {
        .failure
    }

    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {}

    func export(
        logRecords: [ReadableLogRecord],
        explicitTimeout: TimeInterval?
    ) async -> ExportResult {
        .failure
    }

    func forceFlush(explicitTimeout: TimeInterval?) async -> ExportResult {
        .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) async {}
}
