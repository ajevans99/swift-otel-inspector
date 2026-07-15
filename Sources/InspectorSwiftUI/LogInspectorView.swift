import InspectorCore
import SwiftUI

public struct LogInspectorView: View {
    @StateObject private var model: LogInspectorModel
    @State private var selectedLogID: UUID?

    public init(store: LogStore) {
        _model = StateObject(wrappedValue: LogInspectorModel(store: store))
    }

    public var body: some View {
        NavigationSplitView {
            Group {
                if model.filteredLogs.isEmpty {
                    LogPlaceholder(
                        title: "No Logs",
                        systemImage: "text.alignleft",
                        message: "Matching log records will appear here."
                    )
                } else {
                    List(model.filteredLogs, selection: $selectedLogID) { log in
                        LogRow(log: log)
                            .tag(log.id)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Logs")
            .searchable(text: $model.searchText, prompt: "Message, service, attribute, or trace")
            .toolbar {
                Menu {
                    Picker("Severity", selection: $model.severityFilter) {
                        ForEach(LogSeverityFilter.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Service", selection: $model.selectedService) {
                        Text("All services").tag(String?.none)
                        ForEach(model.availableServices, id: \.self) {
                            Text($0).tag(Optional($0))
                        }
                    }
                    Toggle("Correlated only", isOn: $model.correlatedOnly)
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        } detail: {
            if let selectedLog {
                LogDetailView(log: selectedLog)
            } else {
                LogPlaceholder(
                    title: "Select a Log",
                    systemImage: "doc.text.magnifyingglass",
                    message: "Choose a record to inspect its structured data."
                )
            }
        }
    }

    private var selectedLog: LogSnapshot? {
        model.filteredLogs.first { $0.id == selectedLogID }
    }
}

private struct LogPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LogRow: View {
    let log: LogSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LogStyle.color(for: log.severity))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    SeverityBadge(severity: log.severity)
                    Text(log.resource.serviceName ?? "unknown service")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(LogStyle.time(log.timestamp))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(log.message)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    if let eventName = log.eventName {
                        Label(eventName, systemImage: "bolt.fill")
                    }
                    if log.traceID != nil {
                        Label("Correlated", systemImage: "link")
                    }
                    if !log.attributes.isEmpty {
                        Label("\(log.attributes.count)", systemImage: "curlybraces")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct LogDetailView: View {
    let log: LogSnapshot

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SeverityBadge(severity: log.severity)
                        Text(log.resource.serviceName ?? "unknown service")
                            .foregroundStyle(.secondary)
                    }
                    Text(log.message)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(InspectorFormatting.timestamp(log.timestamp))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Context") {
                if let eventName = log.eventName {
                    LogDetailRow(label: "Event", value: eventName)
                }
                LogDetailRow(label: "Scope", value: log.instrumentationScope.name)
                if let traceID = log.traceID {
                    LogDetailRow(label: "Trace ID", value: traceID.rawValue, monospaced: true)
                }
                if let spanID = log.spanID {
                    LogDetailRow(label: "Span ID", value: spanID.rawValue, monospaced: true)
                }
                if let observedTimestamp = log.observedTimestamp {
                    LogDetailRow(
                        label: "Observed",
                        value: InspectorFormatting.timestamp(observedTimestamp)
                    )
                }
            }

            LogAttributeSection(title: "Attributes", attributes: log.attributes)
            LogAttributeSection(title: "Resource", attributes: log.resource.attributes)
            LogAttributeSection(
                title: "Instrumentation scope",
                attributes: log.instrumentationScope.attributes
            )
        }
        .navigationTitle(log.severity?.text ?? "Log")
    }
}

private struct SeverityBadge: View {
    let severity: LogSeverity?

    var body: some View {
        Text(severity?.text ?? "UNSET")
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(LogStyle.color(for: severity))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(LogStyle.color(for: severity).opacity(0.12), in: Capsule())
            .accessibilityLabel("Severity \(severity?.text ?? "unset")")
    }
}

private struct LogAttributeSection: View {
    let title: String
    let attributes: [String: TelemetryAttributeValue]

    var body: some View {
        if !attributes.isEmpty {
            Section(title) {
                ForEach(attributes.sorted(by: { $0.key < $1.key }), id: \.key) {
                    LogDetailRow(label: $0.key, value: $0.value.displayValue)
                }
            }
        }
    }
}

private struct LogDetailRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .textSelection(.enabled)
        }
    }
}

enum LogStyle {
    static func color(for severity: LogSeverity?) -> Color {
        switch severity?.rawValue ?? 0 {
        case 21...: .purple
        case 17 ..< 21: .red
        case 13 ..< 17: .orange
        case 9 ..< 13: .blue
        case 5 ..< 9: .secondary
        default: .gray
        }
    }

    static func time(_ timestamp: TelemetryTimestamp) -> String {
        timestamp.date.formatted(
            .dateTime.hour().minute().second().secondFraction(.fractional(3))
        )
    }
}
