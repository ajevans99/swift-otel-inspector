import InspectorCore
import InspectorSwiftUI
import Testing

@Test
func cumulativeCounterRatesHandleResets() {
    let series = MetricSeriesSnapshot(
        points: [
            point(start: 0, end: 1, value: 10),
            point(start: 0, end: 2, value: 14),
            point(start: 2, end: 3, value: 2),
        ]
    )
    let metric = MetricSnapshot(
        name: "requests",
        kind: .sum(monotonic: true),
        temporality: .cumulative,
        series: [series]
    )

    let samples = MetricPresentation.chartSamples(metric: metric, series: series)

    #expect(samples.map(\.value) == [4, 2])
    #expect(samples.map(\.isReset) == [false, true])
}

@Test
func deltaCounterRatesUseCollectionWindow() {
    let series = MetricSeriesSnapshot(
        points: [point(start: 1, end: 3, value: 8)]
    )
    let metric = MetricSnapshot(
        name: "requests",
        kind: .sum(monotonic: true),
        temporality: .delta,
        series: [series]
    )

    #expect(MetricPresentation.chartSamples(metric: metric, series: series).map(\.value) == [4])
}

@Test
func histogramBucketsIncludeUnderflowAndOverflow() {
    let buckets = MetricPresentation.explicitHistogramBuckets(
        MetricHistogramSnapshot(
            count: 6,
            sum: 42,
            boundaries: [10, 20],
            bucketCounts: [1, 2, 3]
        )
    )

    #expect(buckets.map(\.label) == ["<= 10", "10-20", "> 20"])
    #expect(buckets.map(\.count) == [1, 2, 3])
}

@Test @MainActor
func metricModelFiltersTypeServiceAndAttributes() async {
    let store = MetricStore(clock: { timestamp(10_000_000_000) })
    let model = MetricInspectorModel(store: store)
    await store.insert([
        MetricSnapshot(
            name: "queue.depth",
            kind: .gauge,
            temporality: .cumulative,
            resource: ResourceSnapshot(attributes: ["service.name": .string("app")]),
            series: [
                MetricSeriesSnapshot(
                    attributes: ["queue": .string("outbox")],
                    points: [point(start: 0, end: 1, value: 3)]
                ),
            ]
        ),
    ])
    for _ in 0 ..< 20 where model.metrics.isEmpty {
        try? await Task.sleep(for: .milliseconds(5))
    }

    model.kindFilter = .gauge
    model.selectedService = "app"
    model.searchText = "OUTBOX"
    #expect(model.filteredMetrics.map(\.name) == ["queue.depth"])
    model.kindFilter = .sum
    #expect(model.filteredMetrics.isEmpty)
}

private func point(start: UInt64, end: UInt64, value: Int64) -> MetricPointSnapshot {
    MetricPointSnapshot(
        startTime: timestamp(start * 1_000_000_000),
        endTime: timestamp(end * 1_000_000_000),
        value: .number(.integer(value))
    )
}

private func timestamp(_ value: UInt64) -> TelemetryTimestamp {
    TelemetryTimestamp(nanosecondsSinceEpoch: value)
}
