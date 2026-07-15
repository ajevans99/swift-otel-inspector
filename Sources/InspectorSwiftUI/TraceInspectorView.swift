import InspectorCore
import SwiftUI

public struct TraceInspectorView: View {
    @StateObject private var model: TraceInspectorModel
    @State private var selectedTraceID: TraceID?

    public init(store: TraceStore) {
        _model = StateObject(wrappedValue: TraceInspectorModel(store: store))
    }

    public var body: some View {
        NavigationSplitView {
            traceList
                .navigationTitle("Traces")
                .searchable(text: $model.searchText, prompt: "Name, service, or trace ID")
                .toolbar {
                    Toggle(isOn: $model.errorsOnly) {
                        Label("Errors only", systemImage: "exclamationmark.triangle")
                    }
                }
        } detail: {
            if let trace = selectedTrace {
                TraceDetailView(trace: trace)
            } else {
                InspectorPlaceholderView()
            }
        }
    }

    private var selectedTrace: TraceSnapshot? {
        model.traces.first { $0.traceID == selectedTraceID }
    }

    @ViewBuilder
    private var traceList: some View {
        if model.filteredTraces.isEmpty {
            InspectorPlaceholderView()
        } else {
            List(model.filteredTraces, selection: $selectedTraceID) { trace in
                TraceRow(trace: trace)
                    .tag(trace.traceID)
            }
        }
    }
}

private struct TraceRow: View {
    let trace: TraceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trace.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if trace.containsError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Contains error")
                }
            }
            HStack {
                Text("\(trace.spans.count) spans")
                Spacer()
                if let start = trace.startTime, let end = trace.endTime {
                    let duration = end.nanosecondsSinceEpoch >= start.nanosecondsSinceEpoch
                        ? end.nanosecondsSinceEpoch - start.nanosecondsSinceEpoch
                        : 0
                    Text(InspectorFormatting.duration(duration))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(trace.traceID.rawValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

private struct TraceDetailView: View {
    let trace: TraceSnapshot
    @State private var selectedSpanID: SpanID?

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Trace tree") {
                    OutlineGroup(trace.roots, children: \.outlineChildren) { node in
                        Button {
                            selectedSpanID = node.span.spanID
                        } label: {
                            SpanTreeRow(node: node)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 180)

            Divider()

            if let span = selectedSpan {
                SpanDetailView(span: span)
            } else {
                Text("Select a span to inspect its details.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(trace.displayName)
        .onAppear {
            selectedSpanID = selectedSpanID ?? trace.roots.first?.span.spanID
        }
    }

    private var selectedSpan: SpanSnapshot? {
        trace.spans.first { $0.spanID == selectedSpanID }
    }
}

private struct SpanTreeRow: View {
    let node: SpanTreeNode

    var body: some View {
        HStack {
            Image(systemName: node.span.status.isError ? "xmark.circle.fill" : "circle.fill")
                .font(.caption)
                .foregroundStyle(node.span.status.isError ? .red : .green)
            VStack(alignment: .leading) {
                Text(node.span.name)
                HStack {
                    Text(node.span.resource.serviceName ?? "unknown service")
                    Text(InspectorFormatting.duration(node.span.durationNanoseconds))
                    if node.isOrphan {
                        Text("orphan")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpanDetailView: View {
    let span: SpanSnapshot

    var body: some View {
        List {
            Section("Span") {
                DetailRow(label: "Name", value: span.name)
                DetailRow(label: "Service", value: span.resource.serviceName ?? "unknown")
                DetailRow(label: "Kind", value: InspectorFormatting.kind(span.kind))
                DetailRow(label: "Status", value: InspectorFormatting.status(span.status))
                DetailRow(label: "Duration", value: InspectorFormatting.duration(span.durationNanoseconds))
                DetailRow(label: "Started", value: InspectorFormatting.timestamp(span.startTime))
                DetailRow(label: "Trace ID", value: span.traceID.rawValue, monospaced: true)
                DetailRow(label: "Span ID", value: span.spanID.rawValue, monospaced: true)
                if let parentSpanID = span.parentSpanID {
                    DetailRow(label: "Parent span ID", value: parentSpanID.rawValue, monospaced: true)
                }
            }

            AttributeSection(title: "Attributes", attributes: span.attributes)
            AttributeSection(title: "Resource", attributes: span.resource.attributes)

            if !span.events.isEmpty {
                Section("Events") {
                    ForEach(span.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name)
                                .font(.headline)
                            Text(InspectorFormatting.timestamp(event.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(event.attributes.sorted(by: { $0.key < $1.key }), id: \.key) {
                                DetailRow(label: $0.key, value: $0.value.displayValue)
                            }
                        }
                    }
                }
            }

            if !span.links.isEmpty {
                Section("Links") {
                    ForEach(span.links) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.traceID.rawValue)
                                .font(.caption.monospaced())
                            Text(link.spanID.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct AttributeSection: View {
    let title: String
    let attributes: [String: TelemetryAttributeValue]

    var body: some View {
        if !attributes.isEmpty {
            Section(title) {
                ForEach(attributes.sorted(by: { $0.key < $1.key }), id: \.key) {
                    DetailRow(label: $0.key, value: $0.value.displayValue)
                }
            }
        }
    }
}

private struct DetailRow: View {
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

private extension SpanTreeNode {
    var outlineChildren: [SpanTreeNode]? {
        children.isEmpty ? nil : children
    }
}
