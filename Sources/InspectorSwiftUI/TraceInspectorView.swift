import InspectorCore
import SwiftUI

public struct TraceInspectorView: View {
    @StateObject private var model: TraceInspectorModel
    @State private var selectedTraceID: TraceID?

    public init(store: TraceStore, logStore: LogStore? = nil) {
        _model = StateObject(wrappedValue: TraceInspectorModel(store: store, logStore: logStore))
    }

    public var body: some View {
        NavigationSplitView {
            traceList
                .navigationTitle("Traces")
                .searchable(text: $model.searchText, prompt: "Name, service, or trace ID")
                .toolbar {
                    Menu {
                        Picker("Status", selection: $model.statusFilter) {
                            ForEach(TraceStatusFilter.allCases) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        Picker("Service", selection: $model.selectedService) {
                            Text("All services").tag(String?.none)
                            ForEach(model.availableServices, id: \.self) {
                                Text($0).tag(Optional($0))
                            }
                        }
                        Picker("Sort", selection: $model.sortOrder) {
                            ForEach(TraceSortOrder.allCases) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    attributeFilters
                }
        } detail: {
            if let trace = selectedTrace {
                TraceDetailView(trace: trace, logs: model.logs)
            } else {
                InspectorPlaceholderView()
            }
        }
    }

    private var attributeFilters: some View {
        VStack(spacing: 6) {
            TextField("Attribute key", text: $model.attributeKey)
            TextField("Attribute value", text: $model.attributeValue)
        }
        .textFieldStyle(.roundedBorder)
        .padding(8)
        .background(.bar)
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
    private enum Presentation: String, CaseIterable, Identifiable {
        case tree = "Tree"
        case waterfall = "Waterfall"
        case timeline = "Timeline"

        var id: Self { self }
    }

    let trace: TraceSnapshot
    let logs: [LogSnapshot]
    @State private var selectedSpanID: SpanID?
    @State private var presentation: Presentation = .tree

    var body: some View {
        VStack(spacing: 0) {
            Picker("Presentation", selection: $presentation) {
                ForEach(Presentation.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch presentation {
                case .tree:
                    traceTree
                case .waterfall:
                    SpanWaterfallView(trace: trace, selectedSpanID: $selectedSpanID)
                case .timeline:
                    TraceTimelineView(
                        trace: trace,
                        logs: logs,
                        selectedSpanID: $selectedSpanID
                    )
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

    private var traceTree: some View {
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
    }
}

private struct TraceTimelineView: View {
    let trace: TraceSnapshot
    let logs: [LogSnapshot]
    @Binding var selectedSpanID: SpanID?

    var body: some View {
        List(TraceTimelineItem.items(for: trace, logs: logs)) { item in
            Button {
                selectedSpanID = item.spanID
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(color(for: item.kind))
                            .frame(width: 9, height: 9)
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 1, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(LogStyle.time(item.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
    }

    private func color(for kind: TraceTimelineItem.Kind) -> Color {
        switch kind {
        case .spanStarted: .green
        case .spanEnded: .secondary
        case .spanEvent: .orange
        case let .log(severity): LogStyle.color(for: severity)
        }
    }
}

private struct SpanWaterfallView: View {
    let trace: TraceSnapshot
    @Binding var selectedSpanID: SpanID?

    private let labelWidth: CGFloat = 150
    private let rowHeight: CGFloat = 30

    var body: some View {
        let items = SpanWaterfallLayout.items(for: trace)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.span.name)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(item.depth) * 10)
                            .frame(width: labelWidth, alignment: .leading)
                        GeometryReader { geometry in
                            let availableWidth = max(1, geometry.size.width)
                            Button {
                                selectedSpanID = item.span.spanID
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.span.status.isError ? Color.red : Color.accentColor)
                                    .overlay(alignment: .leading) {
                                        if item.span.spanID == selectedSpanID {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(.primary, lineWidth: 2)
                                        }
                                    }
                                    .frame(
                                        width: max(3, availableWidth * item.widthFraction),
                                        height: 18
                                    )
                                    .offset(x: availableWidth * item.offsetFraction)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(item.span.name), \(InspectorFormatting.duration(item.span.durationNanoseconds))"
                            )
                        }
                        .frame(width: 420, height: rowHeight)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding()
        }
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
