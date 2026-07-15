import Foundation
import InspectorCore
import Testing

@Test
func metricStoreMergesSeriesAndOrdersPoints() async throws {
    let store = MetricStore(clock: { timestamp(100) })
    let first = metric(
        series: [
            MetricSeriesSnapshot(
                attributes: ["route": .string("/sync")],
                points: [numberPoint(time: 20, value: 2), numberPoint(time: 10, value: 1)]
            ),
        ]
    )
    let second = metric(
        series: [
            MetricSeriesSnapshot(
                attributes: ["route": .string("/sync")],
                points: [numberPoint(time: 30, value: 3)]
            ),
        ]
    )

    await store.insert([first, second])

    let stored = try #require(await store.metrics().first)
    #expect(stored.series.count == 1)
    #expect(stored.series[0].points.map(\.endTime.nanosecondsSinceEpoch) == [10, 20, 30])
}

@Test
func metricStoreEnforcesPointAndSeriesLimitsDeterministically() async throws {
    let store = MetricStore(
        configuration: MetricStoreConfiguration(
            maximumMetricCount: 2,
            maximumSeriesCount: 2,
            maximumSeriesPerMetric: 2,
            maximumPointsPerSeries: 2,
            maximumEstimatedBytes: 1_000_000,
            maximumAge: .seconds(1),
            maximumAttributeValueBytes: 100
        ),
        clock: { timestamp(100) }
    )
    await store.insert([
        metric(
            series: [
                series("a", times: [10, 20, 30]),
                series("b", times: [20, 40]),
                series("c", times: [30, 50]),
            ]
        ),
    ])

    let stored = try #require(await store.metrics().first)
    #expect(stored.series.map { $0.attributes["series"] } == [.string("b"), .string("c")])
    #expect(stored.series.flatMap(\.points).count == 4)
    #expect(stored.series.first { $0.attributes["series"] == .string("c") }?
        .points.map(\.endTime.nanosecondsSinceEpoch) == [30, 50])
}

@Test
func metricStoreRedactsAttributesBeforeCreatingSeriesIdentity() async throws {
    let store = MetricStore(
        configuration: MetricStoreConfiguration(maximumAttributeValueBytes: 3),
        redactor: { key, value in key == "secret" ? nil : value },
        clock: { timestamp(100) }
    )
    await store.insert([
        metric(
            series: [
                MetricSeriesSnapshot(
                    attributes: [
                        "secret": .string("remove"),
                        "region": .string("north"),
                    ],
                    points: [numberPoint(time: 100, value: 1)]
                ),
            ]
        ),
    ])

    let series = try #require(await store.metrics().first?.series.first)
    #expect(series.attributes["secret"] == nil)
    #expect(series.attributes["region"] == .string("nor"))
    #expect(series.id == MetricSeriesSnapshot(
        attributes: ["region": .string("nor")],
        points: []
    ).id)
}

@Test
func metricIdentitySeparatesDistinctStreamDescriptors() {
    let base = metric(series: [series("a", times: [1])])
    let delta = MetricSnapshot(
        name: base.name,
        description: base.description,
        unit: base.unit,
        kind: base.kind,
        temporality: .delta,
        resource: base.resource,
        instrumentationScope: base.instrumentationScope,
        series: base.series
    )
    let schema = MetricSnapshot(
        name: base.name,
        description: base.description,
        unit: base.unit,
        kind: base.kind,
        temporality: base.temporality,
        resource: ResourceSnapshot(
            attributes: base.resource.attributes,
            schemaURL: "https://opentelemetry.io/schemas/1.30.0"
        ),
        instrumentationScope: base.instrumentationScope,
        series: base.series
    )

    #expect(base.id != delta.id)
    #expect(base.id != schema.id)
}

@Test
func metricStorePublishesScheduledExpirationWithoutFurtherIngestion() async throws {
    let now = TelemetryTimestamp(date: Date())
    let store = MetricStore(
        configuration: MetricStoreConfiguration(maximumAge: .milliseconds(20))
    )
    let stream = await store.changes()
    var iterator = stream.makeAsyncIterator()
    _ = await iterator.next()

    await store.insert([
        metric(
            series: [
                MetricSeriesSnapshot(
                    points: [
                        MetricPointSnapshot(
                            startTime: now,
                            endTime: now,
                            value: .number(.integer(1))
                        ),
                    ]
                ),
            ]
        ),
    ])
    #expect(try #require(await iterator.next()).first?.series.first?.points.count == 1)

    let expiration = await iterator.next()
    #expect(try #require(expiration).isEmpty)
}

private func metric(series: [MetricSeriesSnapshot]) -> MetricSnapshot {
    MetricSnapshot(
        name: "http.server.requests",
        unit: "{request}",
        kind: .sum(monotonic: true),
        temporality: .cumulative,
        resource: ResourceSnapshot(attributes: ["service.name": .string("api")]),
        series: series
    )
}

private func series(_ name: String, times: [UInt64]) -> MetricSeriesSnapshot {
    MetricSeriesSnapshot(
        attributes: ["series": .string(name)],
        points: times.map { numberPoint(time: $0, value: Int64($0)) }
    )
}

private func numberPoint(time: UInt64, value: Int64) -> MetricPointSnapshot {
    MetricPointSnapshot(
        startTime: timestamp(1),
        endTime: timestamp(time),
        value: .number(.integer(value))
    )
}

private func timestamp(_ value: UInt64) -> TelemetryTimestamp {
    TelemetryTimestamp(nanosecondsSinceEpoch: value)
}
