import Foundation
import InspectorCore
import Testing

@Test
func logStoreOrdersNewestAndCorrelatesByTrace() async {
    let traceID = TraceID(rawValue: "trace")
    let store = LogStore(clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) })
    await store.insert([
        makeLog(id: 1, timestamp: 10, traceID: traceID),
        makeLog(id: 2, timestamp: 20),
        makeLog(id: 3, timestamp: 30, traceID: traceID),
    ])

    #expect(await store.logs().map(\.timestamp.nanosecondsSinceEpoch) == [30, 20, 10])
    #expect(await store.logs(traceID: traceID).map(\.timestamp.nanosecondsSinceEpoch) == [30, 10])
}

@Test
func logStoreRedactsTruncatesAndEvicts() async throws {
    let store = LogStore(
        configuration: LogStoreConfiguration(
            maximumLogCount: 1,
            maximumEstimatedBytes: 100_000,
            maximumAge: .seconds(100),
            maximumAttributeValueBytes: 4
        ),
        redactor: { key, value in key == "secret" ? nil : value },
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) }
    )
    await store.insert([
        makeLog(id: 1, timestamp: 10),
        LogSnapshot(
            id: uuid(2),
            timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: 20),
            body: .string("abcdef"),
            attributes: [
                "secret": .string("hidden"),
                "visible": .string("123456"),
            ]
        ),
    ])

    let log = try #require(await store.logs().first)
    #expect(await store.statistics().logCount == 1)
    #expect(log.body == .string("abcd"))
    #expect(log.attributes["secret"] == nil)
    #expect(log.attributes["visible"] == .string("1234"))
}

@Test
func logStorePublishesScheduledExpiration() async throws {
    let now = TelemetryTimestamp(date: Date())
    let store = LogStore(
        configuration: LogStoreConfiguration(maximumAge: .milliseconds(20))
    )
    let stream = await store.changes()
    var iterator = stream.makeAsyncIterator()
    _ = await iterator.next()

    await store.insert([
        LogSnapshot(id: uuid(1), timestamp: now, body: .string("temporary")),
    ])
    #expect(try #require(await iterator.next()).count == 1)
    #expect(try #require(await iterator.next()).isEmpty)
}

private func makeLog(
    id: UInt8,
    timestamp: UInt64,
    traceID: TraceID? = nil
) -> LogSnapshot {
    LogSnapshot(
        id: uuid(id),
        timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: timestamp),
        traceID: traceID,
        severity: .info,
        body: .string("message \(id)")
    )
}

private func uuid(_ value: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
