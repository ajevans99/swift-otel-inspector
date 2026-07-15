import InspectorCore
import InspectorSwiftUI
import Testing

@Test(arguments: [
    (999, "999 ns"),
    (1_000, "1.00 us"),
    (1_000_000, "1.00 ms"),
    (1_000_000_000, "1.00 s"),
])
func durationFormatting(input: Int, expected: String) {
    #expect(InspectorFormatting.duration(UInt64(input)) == expected)
}

@Test @MainActor
func modelFiltersByErrorAndService() async {
    let store = TraceStore(
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 2) }
    )
    let model = TraceInspectorModel(store: store)
    let traceID = TraceID(rawValue: "trace")
    await store.insert([
        SpanSnapshot(
            traceID: traceID,
            spanID: SpanID(rawValue: "span"),
            name: "request",
            startTime: TelemetryTimestamp(nanosecondsSinceEpoch: 1),
            endTime: TelemetryTimestamp(nanosecondsSinceEpoch: 2),
            status: .error(message: "failed"),
            resource: ResourceSnapshot(attributes: ["service.name": .string("sync-api")])
        ),
    ])

    for _ in 0 ..< 20 where model.traces.isEmpty {
        try? await Task.sleep(for: .milliseconds(5))
    }
    model.statusFilter = .errors
    model.searchText = "SYNC-API"

    #expect(model.filteredTraces.count == 1)
    model.searchText = "other"
    #expect(model.filteredTraces.isEmpty)
    model.stopObserving()
}

@Test @MainActor
func modelFiltersAttributesAndSortsLongestFirst() async {
    let store = TraceStore(clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) })
    let model = TraceInspectorModel(store: store)
    await store.insert([
        testSpan(trace: "short", span: "01", start: 10, end: 20, region: "east"),
        testSpan(trace: "long", span: "02", start: 10, end: 80, region: "west"),
    ])
    for _ in 0 ..< 20 where model.traces.count < 2 {
        try? await Task.sleep(for: .milliseconds(5))
    }

    model.attributeKey = "region"
    model.attributeValue = "west"
    #expect(model.filteredTraces.map(\.traceID.rawValue) == ["long"])

    model.attributeValue = ""
    model.sortOrder = .longest
    #expect(model.filteredTraces.map(\.traceID.rawValue) == ["long", "short"])
    model.stopObserving()
}

@Test
func waterfallLayoutPreservesTreeDepthAndRelativeTiming() throws {
    let root = testSpan(trace: "trace", span: "01", start: 0, end: 100, region: "east")
    let child = SpanSnapshot(
        traceID: root.traceID,
        spanID: SpanID(rawValue: "02"),
        parentSpanID: root.spanID,
        name: "child",
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: 25),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: 75)
    )

    let items = SpanWaterfallLayout.items(
        for: TraceSnapshot(traceID: root.traceID, spans: [child, root])
    )
    let childItem = try #require(items.first { $0.span.spanID == child.spanID })

    #expect(childItem.depth == 1)
    #expect(childItem.offsetFraction == 0.25)
    #expect(childItem.widthFraction == 0.5)
}

@Test @MainActor
func statusFiltersUseExclusiveAggregateTraceStatus() async {
    let store = TraceStore(clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) })
    let model = TraceInspectorModel(store: store)
    let ok = testSpan(trace: "mixed", span: "01", start: 1, end: 2, region: "east")
    let unset = SpanSnapshot(
        traceID: ok.traceID,
        spanID: SpanID(rawValue: "02"),
        name: "unset",
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: 2),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: 3)
    )
    await store.insert([ok, unset])
    for _ in 0 ..< 20 where model.traces.isEmpty {
        try? await Task.sleep(for: .milliseconds(5))
    }

    model.statusFilter = .successful
    #expect(model.filteredTraces.isEmpty)
    model.statusFilter = .unset
    #expect(model.filteredTraces.count == 1)
    model.stopObserving()
}

private func testSpan(
    trace: String,
    span: String,
    start: UInt64,
    end: UInt64,
    region: String
) -> SpanSnapshot {
    SpanSnapshot(
        traceID: TraceID(rawValue: trace),
        spanID: SpanID(rawValue: span),
        name: span,
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: start),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: end),
        attributes: ["deployment.region": .string(region)],
        status: .ok,
        resource: ResourceSnapshot(attributes: ["service.name": .string("service-\(region)")])
    )
}
