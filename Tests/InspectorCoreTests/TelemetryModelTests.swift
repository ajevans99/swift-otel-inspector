import Foundation
import InspectorCore
import Testing

@Test
func durationClampsMalformedTimestamps() {
    let span = makeSpan(
        id: "0000000000000001",
        start: 20,
        end: 10
    )

    #expect(span.durationNanoseconds == 0)
}

@Test
func attributeValuesPreserveMixedNestedData() throws {
    let value = TelemetryAttributeValue.dictionary([
        "attempt": .int(2),
        "flags": .array([.bool(true), .string("retry")]),
        "payload": .bytes(Data([0x01, 0x02])),
    ])

    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(TelemetryAttributeValue.self, from: encoded)

    #expect(decoded == value)
    #expect(value.displayValue.contains("attempt: 2"))
}

@Test
func traceTreeOrdersChildrenAndMarksOrphans() throws {
    let root = makeSpan(id: "0000000000000001", start: 1, end: 20)
    let laterChild = makeSpan(
        id: "0000000000000003",
        parent: root.spanID,
        start: 10,
        end: 12
    )
    let earlierChild = makeSpan(
        id: "0000000000000002",
        parent: root.spanID,
        start: 5,
        end: 8
    )
    let orphan = makeSpan(
        id: "0000000000000004",
        parent: SpanID(rawValue: "ffffffffffffffff"),
        start: 2,
        end: 3
    )

    let trace = TraceSnapshot(
        traceID: root.traceID,
        spans: [laterChild, orphan, root, earlierChild]
    )

    #expect(trace.roots.count == 2)
    let rootNode = try #require(trace.roots.first { $0.span.spanID == root.spanID })
    #expect(rootNode.children.map(\.span.spanID) == [earlierChild.spanID, laterChild.spanID])
    #expect(trace.roots.first { $0.span.spanID == orphan.spanID }?.isOrphan == true)
}

@Test
func traceTreeSurfacesCyclesAsOrphans() {
    let firstID = SpanID(rawValue: "0000000000000001")
    let secondID = SpanID(rawValue: "0000000000000002")
    let first = makeSpan(id: firstID.rawValue, parent: secondID, start: 1, end: 2)
    let second = makeSpan(id: secondID.rawValue, parent: firstID, start: 2, end: 3)

    let roots = TraceSnapshot(traceID: first.traceID, spans: [first, second]).roots

    #expect(roots.count == 2)
    #expect(roots.allSatisfy { $0.isOrphan })
}

private func makeSpan(
    id: String,
    parent: SpanID? = nil,
    start: UInt64,
    end: UInt64,
    status: InspectorSpanStatus = .unset
) -> SpanSnapshot {
    SpanSnapshot(
        traceID: TraceID(rawValue: "4fd0b7e26aa34d1f9f75d49e6bc22a1b"),
        spanID: SpanID(rawValue: id),
        parentSpanID: parent,
        name: "test",
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: start),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: end),
        status: status
    )
}
