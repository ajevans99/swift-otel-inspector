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
    model.errorsOnly = true
    model.searchText = "SYNC-API"

    #expect(model.filteredTraces.count == 1)
    model.searchText = "other"
    #expect(model.filteredTraces.isEmpty)
    model.stopObserving()
}
