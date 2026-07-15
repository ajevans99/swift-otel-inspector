import InspectorCore
import InspectorOpenTelemetry
import InspectorSwiftUI
import OpenTelemetryApi
import OpenTelemetrySdk
import StdoutExporter
import SwiftUI

@main
struct InspectorExampleApp: App {
    private let store: TraceStore
    private let tracerProvider: TracerProviderSdk

    init() {
        let store = TraceStore()
        let inspector = InspectorSpanExporter(store: store)
        let exporters = MultiSpanExporter(
            spanExporters: [inspector, StdoutSpanExporter()]
        )
        let processor = SimpleSpanProcessor(spanExporter: exporters)
        let provider = TracerProviderSdk(
            resource: Resource(attributes: [
                "service.name": .string("InspectorExample"),
                "service.version": .string("0.1.0"),
            ]),
            spanProcessors: [processor]
        )
        self.store = store
        tracerProvider = provider

        let tracer = provider.get(
            instrumentationName: "SwiftOTelInspector.Example",
            instrumentationVersion: "0.1.0"
        )
        let root = tracer.spanBuilder(spanName: "example.refresh")
            .setSpanKind(spanKind: .internal)
            .startSpan()
        let child = tracer.spanBuilder(spanName: "GET /example")
            .setParent(root)
            .setSpanKind(spanKind: .client)
            .setAttribute(key: "server.address", value: "example.test")
            .startSpan()
        child.status = .error(description: "Example failure")
        child.addEvent(
            name: "exception",
            attributes: ["exception.type": .string("ExampleError")]
        )
        child.end()
        root.status = .error(description: "Child request failed")
        root.end()
        provider.forceFlush()
    }

    var body: some Scene {
        WindowGroup {
            TraceInspectorView(store: store)
        }
    }
}
