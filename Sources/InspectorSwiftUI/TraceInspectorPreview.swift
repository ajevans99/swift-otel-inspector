#if DEBUG
import Foundation
import InspectorCore
import SwiftUI

#Preview("Failed distributed sync") {
    TraceInspectorView(store: previewStore())
}

@MainActor
private func previewStore() -> TraceStore {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/otlp/sync-trace.json")
    let store = TraceStore(
        configuration: TraceStoreConfiguration(maximumAge: .seconds(60 * 60 * 24 * 365 * 10)),
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 1_720_454_400_380_000_000) }
    )
    if
        let data = try? Data(contentsOf: fixtureURL),
        let spans = try? OTLPPreviewFixtureDecoder.decode(data)
    {
        Task {
            await store.insert(spans)
        }
    }
    return store
}
#endif
