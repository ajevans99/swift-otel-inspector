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

@Test
func metricFixtureDrivesChartPreviews() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/otlp/sync-metrics.json")
    let metrics = try OTLPPreviewFixtureDecoder.decodeMetrics(Data(contentsOf: fixtureURL))

    #expect(metrics.count == 8)
    #expect(Set(metrics.compactMap(\.resource.serviceName)) == ["ExampleSyncApp", "sync-api"])
    #expect(metrics.contains { $0.kind == .sum(monotonic: true) })
    #expect(metrics.contains { $0.kind == .gauge })
    #expect(metrics.contains { $0.kind == .histogram })
    #expect(metrics.flatMap(\.series).flatMap(\.points).flatMap(\.exemplars).count == 3)
}
