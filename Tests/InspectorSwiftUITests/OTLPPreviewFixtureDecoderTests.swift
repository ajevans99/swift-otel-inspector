import Foundation
import InspectorCore
@testable import InspectorSwiftUI
import Testing

@Test
func fixtureDrivesCompleteDistributedTracePreview() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/otlp/sync-trace.json")
    let spans = try OTLPPreviewFixtureDecoder.decode(Data(contentsOf: fixtureURL))
    let traceID = try #require(spans.first?.traceID)
    let trace = TraceSnapshot(traceID: traceID, spans: spans)

    #expect(spans.count == 6)
    #expect(Set(spans.compactMap(\.resource.serviceName)) == ["ExampleSyncApp", "sync-api"])
    #expect(trace.roots.count == 1)
    #expect(trace.containsError)
    #expect(spans.flatMap(\.events).contains { $0.name == "exception" })
    #expect(spans.flatMap(\.links).count == 1)
}
