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
    private let logStore: LogStore
    private let tracerProvider: TracerProviderSdk
    private let loggerProvider: LoggerProviderSdk

    init() {
        let store = TraceStore()
        let logStore = LogStore()
        let inspector = InspectorSpanExporter(store: store)
        let logInspector = InspectorLogExporter(store: logStore)
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
        let loggerProvider = LoggerProviderSdk(
            resource: Resource(attributes: [
                "service.name": .string("InspectorExample"),
                "service.version": .string("0.2.0-dev"),
            ]),
            logRecordProcessors: [
                SimpleLogRecordProcessor(logRecordExporter: logInspector),
            ]
        )
        self.store = store
        self.logStore = logStore
        tracerProvider = provider
        self.loggerProvider = loggerProvider

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
        let logger = loggerProvider.get(
            instrumentationScopeName: "SwiftOTelInspector.Example"
        )
        logger.logRecordBuilder()
            .setTimestamp(Date())
            .setSpanContext(child.context)
            .setSeverity(.info)
            .setBody(.string("Sending example request"))
            .setAttributes(["http.request.method": .string("GET")])
            .emit()
        child.status = .error(description: "Example failure")
        child.addEvent(
            name: "exception",
            attributes: ["exception.type": .string("ExampleError")]
        )
        logger.logRecordBuilder()
            .setTimestamp(Date())
            .setSpanContext(child.context)
            .setSeverity(.error)
            .setBody(.string("Example request failed"))
            .setAttributes([
                "error.type": .string("ExampleError"),
                "http.response.status_code": .int(503),
            ])
            .emit()
        child.end()
        root.status = .error(description: "Child request failed")
        root.end()
        provider.forceFlush()
        _ = logInspector.forceFlush()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                TraceInspectorView(store: store, logStore: logStore)
                    .tabItem {
                        Label("Traces", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                LogInspectorView(store: logStore)
                    .tabItem {
                        Label("Logs", systemImage: "text.alignleft")
                    }
            }
        }
    }
}
