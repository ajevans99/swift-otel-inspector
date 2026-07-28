#if !os(watchOS)

import InspectorCore
import SwiftUI

public enum TraceStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All statuses"
    case errors = "Errors"
    case successful = "Successful"
    case unset = "Unset"

    public var id: Self { self }
}

public enum TraceSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest"
    case oldest = "Oldest"
    case longest = "Longest"
    case errorsFirst = "Errors first"

    public var id: Self { self }
}

@MainActor
public final class TraceInspectorModel: ObservableObject {
    @Published public private(set) var traces: [TraceSnapshot] = []
    @Published public private(set) var logs: [LogSnapshot] = []
    @Published public var searchText = ""
    @Published public var statusFilter: TraceStatusFilter = .all
    @Published public var selectedService: String?
    @Published public var attributeKey = ""
    @Published public var attributeValue = ""
    @Published public var sortOrder: TraceSortOrder = .newest

    private let store: TraceStore
    private var observationTask: Task<Void, Never>?
    private var logObservationTask: Task<Void, Never>?

    public init(store: TraceStore, logStore: LogStore? = nil) {
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
        if let logStore {
            logObservationTask = Task { [weak self, logStore] in
                let changes = await logStore.changes()
                for await logs in changes {
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.logs = logs
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        logObservationTask?.cancel()
    }

    public var filteredTraces: [TraceSnapshot] {
        traces.filter { trace in
            let matchesStatus = traceMatchesStatus(trace)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty || trace.spans.contains {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.resource.serviceName?.localizedCaseInsensitiveContains(query) ?? false)
                    || $0.traceID.rawValue.localizedCaseInsensitiveContains(query)
            }
            let matchesService = selectedService == nil || trace.spans.contains {
                $0.resource.serviceName == selectedService
            }
            let matchesAttribute = traceMatchesAttribute(trace)
            return matchesStatus && matchesQuery && matchesService && matchesAttribute
        }
        .sorted(by: traceOrdering)
    }

    public var availableServices: [String] {
        Set(traces.flatMap(\.spans).compactMap(\.resource.serviceName)).sorted()
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        logObservationTask?.cancel()
        logObservationTask = nil
    }

    private func traceMatchesStatus(_ trace: TraceSnapshot) -> Bool {
        switch statusFilter {
        case .all:
            true
        case .errors:
            trace.containsError
        case .successful:
            !trace.spans.isEmpty && trace.spans.allSatisfy { $0.status == .ok }
        case .unset:
            !trace.containsError && !trace.spans.allSatisfy { $0.status == .ok }
        }
    }

    private func traceMatchesAttribute(_ trace: TraceSnapshot) -> Bool {
        let key = attributeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = attributeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty || !value.isEmpty else {
            return true
        }
        return trace.spans.contains { span in
            func matches(_ attributes: [String: TelemetryAttributeValue]) -> Bool {
                attributes.contains { attribute in
                    let keyMatches = key.isEmpty
                        || attribute.key.localizedCaseInsensitiveContains(key)
                    let valueMatches = value.isEmpty
                        || attribute.value.displayValue.localizedCaseInsensitiveContains(value)
                    return keyMatches && valueMatches
                }
            }
            return matches(span.attributes) || matches(span.resource.attributes)
        }
    }

    private func traceOrdering(_ lhs: TraceSnapshot, _ rhs: TraceSnapshot) -> Bool {
        switch sortOrder {
        case .newest:
            return compareStart(lhs, rhs, descending: true)
        case .oldest:
            return compareStart(lhs, rhs, descending: false)
        case .longest:
            let lhsDuration = duration(lhs)
            let rhsDuration = duration(rhs)
            return lhsDuration == rhsDuration
                ? compareStart(lhs, rhs, descending: true)
                : lhsDuration > rhsDuration
        case .errorsFirst:
            return lhs.containsError == rhs.containsError
                ? compareStart(lhs, rhs, descending: true)
                : lhs.containsError
        }
    }

    private func compareStart(
        _ lhs: TraceSnapshot,
        _ rhs: TraceSnapshot,
        descending: Bool
    ) -> Bool {
        let lhsStart = lhs.startTime?.nanosecondsSinceEpoch ?? 0
        let rhsStart = rhs.startTime?.nanosecondsSinceEpoch ?? 0
        if lhsStart == rhsStart {
            return lhs.traceID < rhs.traceID
        }
        return descending ? lhsStart > rhsStart : lhsStart < rhsStart
    }

    private func duration(_ trace: TraceSnapshot) -> UInt64 {
        guard let start = trace.startTime, let end = trace.endTime else {
            return 0
        }
        return end.nanosecondsSinceEpoch >= start.nanosecondsSinceEpoch
            ? end.nanosecondsSinceEpoch - start.nanosecondsSinceEpoch
            : 0
    }
}


#endif
