import InspectorCore
import SwiftUI

public enum LogSeverityFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All severities"
    case trace = "Trace"
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case fatal = "Fatal"

    public var id: Self { self }

    func contains(_ severity: LogSeverity?) -> Bool {
        guard self != .all else {
            return true
        }
        guard let value = severity?.rawValue else {
            return false
        }
        return switch self {
        case .all: true
        case .trace: (1 ... 4).contains(value)
        case .debug: (5 ... 8).contains(value)
        case .info: (9 ... 12).contains(value)
        case .warning: (13 ... 16).contains(value)
        case .error: (17 ... 20).contains(value)
        case .fatal: value >= 21
        }
    }
}

@MainActor
public final class LogInspectorModel: ObservableObject {
    @Published public private(set) var logs: [LogSnapshot] = []
    @Published public var searchText = ""
    @Published public var severityFilter: LogSeverityFilter = .all
    @Published public var selectedService: String?
    @Published public var correlatedOnly = false

    private var observationTask: Task<Void, Never>?

    public init(store: LogStore) {
        observationTask = Task { [weak self, store] in
            let changes = await store.changes()
            for await logs in changes {
                guard !Task.isCancelled else {
                    return
                }
                self?.logs = logs
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    public var filteredLogs: [LogSnapshot] {
        logs.filter { log in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty
                || log.message.localizedCaseInsensitiveContains(query)
                || (log.eventName?.localizedCaseInsensitiveContains(query) ?? false)
                || (log.resource.serviceName?.localizedCaseInsensitiveContains(query) ?? false)
                || (log.traceID?.rawValue.localizedCaseInsensitiveContains(query) ?? false)
                || log.attributes.contains {
                    $0.key.localizedCaseInsensitiveContains(query)
                        || $0.value.displayValue.localizedCaseInsensitiveContains(query)
                }
            return severityFilter.contains(log.severity)
                && (selectedService == nil || log.resource.serviceName == selectedService)
                && (!correlatedOnly || log.traceID != nil)
                && matchesQuery
        }
    }

    public var availableServices: [String] {
        Set(logs.compactMap(\.resource.serviceName)).sorted()
    }
}
