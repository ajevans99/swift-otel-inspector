import InspectorCore
import Testing

@Test
func storeReplacesDuplicateSpanAndOrdersNewestTraceFirst() async throws {
    let now = TelemetryTimestamp(nanosecondsSinceEpoch: 1_000)
    let store = TraceStore(
        configuration: TraceStoreConfiguration(maximumAge: .seconds(10)),
        clock: { now }
    )
    let older = makeStoreSpan(trace: "01", span: "01", name: "old", end: 900)
    let newer = makeStoreSpan(trace: "02", span: "02", name: "new", end: 950)
    let replacement = makeStoreSpan(trace: "01", span: "01", name: "replacement", end: 975)

    await store.insert([older, newer, replacement])

    let traces = await store.traces()
    #expect(traces.map(\.traceID.rawValue) == ["01", "02"])
    #expect(traces.first?.spans.first?.name == "replacement")
    #expect(await store.statistics().spanCount == 2)
}

@Test
func storeEvictsOldestSpanDeterministically() async {
    let store = TraceStore(
        configuration: TraceStoreConfiguration(
            maximumSpanCount: 2,
            maximumEstimatedBytes: 100_000,
            maximumAge: .seconds(100)
        ),
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) }
    )

    await store.insert([
        makeStoreSpan(trace: "01", span: "01", end: 10),
        makeStoreSpan(trace: "01", span: "02", end: 20),
        makeStoreSpan(trace: "01", span: "03", end: 30),
    ])

    let spans = await store.traces().flatMap(\.spans)
    #expect(spans.map(\.spanID.rawValue) == ["02", "03"])
}

@Test
func storeAppliesRedactionBeforeUTF8SafeTruncation() async throws {
    let store = TraceStore(
        configuration: TraceStoreConfiguration(
            maximumEstimatedBytes: 100_000,
            maximumAge: .seconds(100),
            maximumAttributeValueBytes: 5
        ),
        redactor: { key, value in
            key == "secret" ? nil : value
        },
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) }
    )
    let span = makeStoreSpan(
        trace: "01",
        span: "01",
        end: 50,
        attributes: [
            "secret": .string("remove me"),
            "unicode": .string("abc😀def"),
        ]
    )

    await store.insert([span])

    let stored = try #require(await store.traces().first?.spans.first)
    #expect(stored.attributes["secret"] == nil)
    #expect(stored.attributes["unicode"] == .string("abc"))
}

@Test
func storeRemovesExpiredSpans() async {
    let store = TraceStore(
        configuration: TraceStoreConfiguration(maximumAge: .nanoseconds(10)),
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) }
    )

    await store.insert([
        makeStoreSpan(trace: "01", span: "01", end: 89),
        makeStoreSpan(trace: "01", span: "02", end: 90),
    ])

    #expect(await store.traces().flatMap(\.spans).map(\.spanID.rawValue) == ["02"])
}

@Test
func changeStreamPublishesInitialAndInsertedSnapshots() async throws {
    let store = TraceStore(
        configuration: TraceStoreConfiguration(maximumAge: .seconds(100)),
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) }
    )
    let stream = await store.changes()
    var iterator = stream.makeAsyncIterator()

    #expect(try #require(await iterator.next()).isEmpty)
    await store.insert([makeStoreSpan(trace: "01", span: "01", end: 50)])
    #expect(try #require(await iterator.next()).first?.spans.count == 1)
}

private func makeStoreSpan(
    trace: String,
    span: String,
    name: String = "span",
    end: UInt64,
    attributes: [String: TelemetryAttributeValue] = [:]
) -> SpanSnapshot {
    SpanSnapshot(
        traceID: TraceID(rawValue: trace),
        spanID: SpanID(rawValue: span),
        name: name,
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: end - 1),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: end),
        attributes: attributes
    )
}
