#if !os(watchOS)

import InspectorCore
import SwiftUI

public enum MetricKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All types"
    case gauge = "Gauges"
    case sum = "Sums"
    case histogram = "Histograms"
    case summary = "Summaries"

    public var id: Self { self }

    func contains(_ kind: MetricKind) -> Bool {
        switch (self, kind) {
        case (.all, _), (.gauge, .gauge), (.sum, .sum),
             (.histogram, .histogram), (.histogram, .exponentialHistogram),
             (.summary, .summary):
            true
        default:
            false
        }
    }
}

@MainActor
public final class MetricInspectorModel: ObservableObject {
    @Published public private(set) var metrics: [MetricSnapshot] = []
    @Published public var searchText = ""
    @Published public var kindFilter: MetricKindFilter = .all
    @Published public var selectedService: String?

    private var observationTask: Task<Void, Never>?

    public init(store: MetricStore) {
        observationTask = Task { [weak self, store] in
            let changes = await store.changes()
            for await metrics in changes {
                guard !Task.isCancelled else {
                    return
                }
                self?.metrics = metrics
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    public var filteredMetrics: [MetricSnapshot] {
        metrics.filter { metric in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty
                || metric.name.localizedCaseInsensitiveContains(query)
                || metric.description.localizedCaseInsensitiveContains(query)
                || metric.instrumentationScope.name.localizedCaseInsensitiveContains(query)
                || (metric.resource.serviceName?.localizedCaseInsensitiveContains(query) ?? false)
                || metric.series.contains { series in
                    series.attributes.contains {
                        $0.key.localizedCaseInsensitiveContains(query)
                            || $0.value.displayValue.localizedCaseInsensitiveContains(query)
                    }
                }
            return kindFilter.contains(metric.kind)
                && (selectedService == nil || metric.resource.serviceName == selectedService)
                && matchesQuery
        }
    }

    public var availableServices: [String] {
        Set(metrics.compactMap(\.resource.serviceName)).sorted()
    }
}


#endif
