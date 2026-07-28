#if !os(watchOS)

#if DEBUG
import Foundation
import InspectorCore
import SwiftUI

#Preview("Live metrics") {
    MetricInspectorView(store: metricPreviewStore())
}

@MainActor
private func metricPreviewStore() -> MetricStore {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/otlp/sync-metrics.json")
    let store = MetricStore(
        configuration: MetricStoreConfiguration(maximumAge: .seconds(60 * 60 * 24 * 365 * 10)),
        clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 1_720_454_400_380_000_000) }
    )
    if
        let data = try? Data(contentsOf: fixtureURL),
        let metrics = try? OTLPPreviewFixtureDecoder.decodeMetrics(data)
    {
        Task {
            await store.insert(metrics)
        }
    }
    return store
}
#endif


#endif
