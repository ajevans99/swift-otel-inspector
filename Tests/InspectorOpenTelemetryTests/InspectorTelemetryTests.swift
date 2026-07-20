import InspectorCore
import InspectorOpenTelemetry
import Testing

@Test
func compositionRetainsOneMatchingStoreSet() {
    let telemetry = InspectorTelemetry()
    let exporters = telemetry.makeExporters()

    #expect(exporters.spanExporter.store === telemetry.traceStore)
    #expect(exporters.logExporter.store === telemetry.logStore)
    #expect(exporters.metricExporter.store === telemetry.metricStore)
}

@Test
func compositionUsesProvidedStores() {
    let traceStore = TraceStore()
    let logStore = LogStore()
    let metricStore = MetricStore()

    let telemetry = InspectorTelemetry(
        traceStore: traceStore,
        logStore: logStore,
        metricStore: metricStore
    )

    #expect(telemetry.traceStore === traceStore)
    #expect(telemetry.logStore === logStore)
    #expect(telemetry.metricStore === metricStore)
}

@Test
func independentlyOwnedPipelinesReceiveDistinctExporters() {
    let telemetry = InspectorTelemetry()

    let stdout = telemetry.makeExporters()
    let otlp = telemetry.makeExporters()

    #expect(stdout.spanExporter !== otlp.spanExporter)
    #expect(stdout.logExporter !== otlp.logExporter)
    #expect(stdout.metricExporter !== otlp.metricExporter)
    #expect(stdout.spanExporter.store === otlp.spanExporter.store)
    #expect(stdout.logExporter.store === otlp.logExporter.store)
    #expect(stdout.metricExporter.store === otlp.metricExporter.store)
}

@Test
func shuttingDownOnePipelineDoesNotDisableAnother() async {
    let telemetry = InspectorTelemetry()
    let stdout = telemetry.makeExporters()
    let otlp = telemetry.makeExporters()

    await stdout.spanExporter.shutdown(explicitTimeout: 1)
    await stdout.logExporter.shutdown(explicitTimeout: 1)
    #expect(await stdout.metricExporter.shutdown() == .success)

    #expect(await otlp.spanExporter.export(spans: [], explicitTimeout: 1) == .success)
    #expect(await otlp.logExporter.export(logRecords: [], explicitTimeout: 1) == .success)
    #expect(await otlp.metricExporter.export(metrics: []) == .success)
}
