import InspectorCore
import InspectorOpenTelemetry
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing

@Test
func sdkMetricsAreStoredWithKindsAndMetadata() async throws {
    let store = MetricStore(
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 0) }
    )
    let exporter = InspectorMetricExporter(store: store)
    let reader = PeriodicMetricReaderBuilder(exporter: exporter)
        .setInterval(timeInterval: 3_600)
        .build()
    let provider = MeterProviderSdk.builder()
        .setResource(resource: Resource(attributes: ["service.name": .string("test-service")]))
        .registerMetricReader(reader: reader)
        .registerView(
            selector: InstrumentSelector.builder().build(),
            view: View.builder().build()
        )
        .build()
    let meter = provider.meterBuilder(name: "InspectorMetricExporterTests").build()
    #expect(type(of: meter) == MeterSdk.self)
    let counter = meter.counterBuilder(name: "http.requests")
        .setDescription("Completed requests")
        .setUnit("{request}")
        .build()
    let gauge = meter.gaugeBuilder(name: "queue.depth").ofLongs().build()
    let upDown = meter.upDownCounterBuilder(name: "requests.in_flight").build()
    let histogram = meter.histogramBuilder(name: "http.duration")
        .setUnit("ms")
        .build()

    counter.add(value: 3, attributes: ["route": .string("/sync")])
    gauge.record(value: 7, attributes: ["queue": .string("outbox")])
    upDown.add(value: 2)
    histogram.record(value: 125, attributes: ["status": .string("503")])

    #expect(provider.forceFlush() == .success)
    #expect(await exporter.flush() == .success)

    let metrics = await store.metrics()
    #expect(metrics.count == 4)
    let requests = try #require(metrics.first { $0.name == "http.requests" })
    #expect(requests.kind == .sum(monotonic: true))
    #expect(requests.temporality == .cumulative)
    #expect(requests.unit == "{request}")
    #expect(requests.description == "Completed requests")
    #expect(requests.resource.serviceName == "test-service")
    #expect(requests.series.first?.attributes["route"] == .string("/sync"))
    #expect(requests.series.first?.points.last?.value == .number(.integer(3)))

    let duration = try #require(metrics.first { $0.name == "http.duration" })
    guard case let .histogram(value) = duration.series.first?.points.last?.value else {
        Issue.record("Expected histogram point")
        return
    }

    #expect(value.count == 1)
    #expect(value.sum == 125)
    #expect(value.minimum == 125)
    #expect(value.maximum == 125)
    #expect(provider.shutdown() == .success)
}

@Test
func metricExporterRejectsCancelledAndPostShutdownExports() async {
    let exporter = InspectorMetricExporter(store: MetricStore())
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await exporter.export(metrics: [])
    }
    #expect(await cancelled.value == .failure)
    #expect(await exporter.shutdown() == .success)
    #expect(await exporter.export(metrics: []) == .failure)
}
