import InspectorCore
import SwiftUI

@MainActor
public final class TraceInspectorModel: ObservableObject {
    @Published public private(set) var traces: [TraceSnapshot] = []
    @Published public var searchText = ""
    @Published public var errorsOnly = false

    private let store: TraceStore
    private var observationTask: Task<Void, Never>?

    public init(store: TraceStore) {
        self.store = store
        observationTask = Task { [weak self, store] in
            let changes = await store.changes()
            for await traces in changes {
                guard !Task.isCancelled else {
                    return
                }
                self?.traces = traces
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    public var filteredTraces: [TraceSnapshot] {
        traces.filter { trace in
            let matchesStatus = !errorsOnly || trace.containsError
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty || trace.spans.contains {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.resource.serviceName?.localizedCaseInsensitiveContains(query) ?? false)
                    || $0.traceID.rawValue.localizedCaseInsensitiveContains(query)
            }
            return matchesStatus && matchesQuery
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
