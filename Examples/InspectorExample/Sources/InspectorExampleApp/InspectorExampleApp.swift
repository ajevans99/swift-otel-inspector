import InspectorCore
import InspectorOpenTelemetry
import InspectorSwiftUI
import OpenTelemetryApi
import OpenTelemetrySdk
import StdoutExporter
import SwiftUI

@main
struct InspectorExampleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = InspectorExampleTelemetry()

    var body: some Scene {
        WindowGroup {
            TabView {
                TraceInspectorView(
                    store: telemetry.traceStore,
                    logStore: telemetry.logStore
                )
                .tabItem {
                    Label("Traces", systemImage: "point.3.connected.trianglepath.dotted")
                }
                LogInspectorView(store: telemetry.logStore)
                    .tabItem {
                        Label("Logs", systemImage: "text.alignleft")
                    }
                MetricInspectorView(store: telemetry.metricStore)
                    .tabItem {
                        Label("Metrics", systemImage: "chart.xyaxis.line")
                    }
            }
            .onAppear {
                telemetry.startMetrics()
            }
            .task(id: scenePhase) {
                if scenePhase == .active {
                    telemetry.startMetrics()
                } else {
                    telemetry.pauseMetrics()
                }
            }
        }
    }
}

@MainActor
private final class InspectorExampleTelemetry: ObservableObject {
    let traceStore = TraceStore()
    let logStore = LogStore()
    let metricStore = MetricStore()

    private let tracerProvider: TracerProviderSdk
    private let loggerProvider: LoggerProviderSdk
    private let meterProvider: MeterProviderSdk
    private let recordMetricTick: (Int) -> Void
    private var metricTask: Task<Void, Never>?

    init() {
        let traceStore = self.traceStore
        let logStore = self.logStore
        let metricStore = self.metricStore
        let resource = Resource(attributes: [
            "service.name": .string("InspectorExample"),
            "service.version": .string("0.2.0-dev"),
            "deployment.environment.name": .string("development"),
        ])

        let spanInspector = InspectorSpanExporter(store: traceStore)
        let spanExporters = MultiSpanExporter(
            spanExporters: [spanInspector, StdoutSpanExporter()]
        )
        let tracerProvider = TracerProviderSdk(
            resource: resource,
            spanProcessors: [SimpleSpanProcessor(spanExporter: spanExporters)]
        )

        let logInspector = InspectorLogExporter(store: logStore)
        let loggerProvider = LoggerProviderSdk(
            resource: resource,
            logRecordProcessors: [
                SimpleLogRecordProcessor(logRecordExporter: logInspector),
            ]
        )

        let metricInspector = InspectorMetricExporter(store: metricStore)
        let metricReader = PeriodicMetricReaderBuilder(exporter: metricInspector)
            .setInterval(timeInterval: 1)
            .build()
        let meterProvider = MeterProviderSdk.builder()
            .setResource(resource: resource)
            .registerMetricReader(reader: metricReader)
            .registerView(
                selector: InstrumentSelector.builder().build(),
                view: View.builder().build()
            )
            .build()
        let meter = meterProvider.meterBuilder(name: "SwiftOTelInspector.Example").build()
        let requestCounter = meter.counterBuilder(name: "example.requests")
            .setDescription("Completed example requests")
            .setUnit("{request}")
            .build()
        let queueDepth = meter.gaugeBuilder(name: "example.queue.depth")
            .ofLongs()
            .setDescription("Items waiting to synchronize")
            .setUnit("{item}")
            .build()
        let requestsInFlight = meter.upDownCounterBuilder(name: "example.requests.in_flight")
            .setDescription("Requests currently in flight")
            .setUnit("{request}")
            .build()
        let requestDuration = meter.histogramBuilder(name: "example.request.duration")
            .setDescription("Example request duration")
            .setUnit("ms")
            .build()
        let durations = [45.0, 90.0, 180.0, 380.0, 125.0]
        recordMetricTick = { tick in
            let failed = tick.isMultiple(of: 4)
            let route = tick.isMultiple(of: 2) ? "/sync" : "/profile"
            let attributes: [String: AttributeValue] = [
                "http.route": .string(route),
                "http.response.status_code": .int(failed ? 503 : 200),
            ]
            requestCounter.add(value: 1, attributes: attributes)
            queueDepth.record(
                value: max(0, 6 - tick % 7),
                attributes: ["queue.name": .string("outbox")]
            )
            requestsInFlight.add(
                value: tick.isMultiple(of: 2) ? 1 : -1,
                attributes: ["http.route": .string(route)]
            )
            requestDuration.record(
                value: durations[tick % durations.count],
                attributes: attributes
            )
        }

        self.tracerProvider = tracerProvider
        self.loggerProvider = loggerProvider
        self.meterProvider = meterProvider
        Self.emitTraceAndLogs(
            tracerProvider: tracerProvider,
            loggerProvider: loggerProvider,
            logInspector: logInspector
        )
        recordMetricTick(0)
        _ = meterProvider.forceFlush()
    }

    func startMetrics() {
        guard metricTask == nil else {
            return
        }
        let recordMetricTick = self.recordMetricTick
        metricTask = Task {
            var tick = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                recordMetricTick(tick)
                tick += 1
            }
        }
    }

    func pauseMetrics() {
        metricTask?.cancel()
        metricTask = nil
        _ = meterProvider.forceFlush()
    }

    private static func emitTraceAndLogs(
        tracerProvider: TracerProviderSdk,
        loggerProvider: LoggerProviderSdk,
        logInspector: InspectorLogExporter
    ) {
        let tracer = tracerProvider.get(
            instrumentationName: "SwiftOTelInspector.Example",
            instrumentationVersion: "0.2.0-dev"
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
        tracerProvider.forceFlush()
        _ = logInspector.forceFlush()
    }
}
