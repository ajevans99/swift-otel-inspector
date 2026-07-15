import Foundation
import InspectorCore
import InspectorOpenTelemetry
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing

@Test
func sdkCompletedSpanIsStored() async throws {
    let store = TraceStore()
    let exporter = InspectorSpanExporter(store: store)
    let processor = SimpleSpanProcessor(spanExporter: exporter)
    let provider = TracerProviderSdk(
        resource: Resource(attributes: ["service.name": .string("test-service")]),
        spanProcessors: [processor]
    )
    let tracer = provider.get(
        instrumentationName: "InspectorSpanExporterTests",
        instrumentationVersion: "1.0"
    )
    let span = tracer.spanBuilder(spanName: "sync.flush")
        .setSpanKind(spanKind: .internal)
        .setAttribute(key: "sync.pending_items", value: 3)
        .startSpan()

    span.status = .error(description: "test failure")
    span.end()
    provider.forceFlush()
    #expect(await exporter.flush(explicitTimeout: 1) == .success)

    let snapshot = try #require(await store.traces().first?.spans.first)
    #expect(snapshot.name == "sync.flush")
    #expect(snapshot.resource.serviceName == "test-service")
    #expect(snapshot.attributes["sync.pending_items"] == .int(3))
    #expect(snapshot.status == .error(message: "test failure"))
    #expect(snapshot.instrumentationScope.name == "InspectorSpanExporterTests")
}

@Test
func shutdownIsIdempotentAndRejectsLaterExports() async {
    let exporter = InspectorSpanExporter(store: TraceStore())

    await exporter.shutdown(explicitTimeout: 1)
    await exporter.shutdown(explicitTimeout: 1)

    #expect(await exporter.export(spans: [], explicitTimeout: 1) == .failure)
}

@Test
func multiExporterReportsFailureWithoutSkippingInspector() async throws {
    let store = TraceStore()
    let inspector = InspectorSpanExporter(store: store)
    let multi = MultiSpanExporter(spanExporters: [FailingExporter(), inspector])

    let result = await multi.export(spans: [], explicitTimeout: 1)

    #expect(result == .failure)
    #expect(await inspector.flush(explicitTimeout: 1) == .success)
    #expect(await store.statistics().spanCount == 0)
}

private final class FailingExporter: SpanExporter, @unchecked Sendable {
    func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval?
    ) -> SpanExporterResultCode {
        .failure
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) {}

    func export(
        spans: [SpanData],
        explicitTimeout: TimeInterval?
    ) async -> SpanExporterResultCode {
        .failure
    }

    func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        .failure
    }

    func shutdown(explicitTimeout: TimeInterval?) async {}
}
