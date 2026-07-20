import InspectorCore

/// A retained set of bounded stores that creates lifecycle-scoped exporters.
///
/// Create one instance for a diagnostics runtime, make a distinct exporter set
/// for each independently owned pipeline, and present the stores from the
/// inspector views.
public struct InspectorTelemetry: Sendable {
    public let traceStore: TraceStore
    public let logStore: LogStore
    public let metricStore: MetricStore

    public init(
        traceConfiguration: TraceStoreConfiguration = TraceStoreConfiguration(),
        logConfiguration: LogStoreConfiguration = LogStoreConfiguration(),
        metricConfiguration: MetricStoreConfiguration = MetricStoreConfiguration(),
        redactor: @escaping AttributeRedactor = { _, value in value }
    ) {
        self.init(
            traceStore: TraceStore(configuration: traceConfiguration, redactor: redactor),
            logStore: LogStore(configuration: logConfiguration, redactor: redactor),
            metricStore: MetricStore(configuration: metricConfiguration, redactor: redactor)
        )
    }

    public init(
        traceStore: TraceStore,
        logStore: LogStore,
        metricStore: MetricStore
    ) {
        self.traceStore = traceStore
        self.logStore = logStore
        self.metricStore = metricStore
    }

    /// Creates exporters that share these stores and one pipeline lifecycle.
    ///
    /// Do not reuse a set across pipelines that can shut down independently.
    public func makeExporters() -> InspectorExporterSet {
        InspectorExporterSet(
            spanExporter: InspectorSpanExporter(store: traceStore),
            logExporter: InspectorLogExporter(store: logStore),
            metricExporter: InspectorMetricExporter(store: metricStore)
        )
    }
}

/// The three signal exporters attached to one runtime pipeline lifecycle.
public struct InspectorExporterSet: Sendable {
    public let spanExporter: InspectorSpanExporter
    public let logExporter: InspectorLogExporter
    public let metricExporter: InspectorMetricExporter

    fileprivate init(
        spanExporter: InspectorSpanExporter,
        logExporter: InspectorLogExporter,
        metricExporter: InspectorMetricExporter
    ) {
        self.spanExporter = spanExporter
        self.logExporter = logExporter
        self.metricExporter = metricExporter
    }
}
