public struct SpanTreeNode: Identifiable, Hashable, Sendable {
    public var id: SpanID { span.spanID }

    public let span: SpanSnapshot
    public let children: [SpanTreeNode]
    public let isOrphan: Bool

    public init(span: SpanSnapshot, children: [SpanTreeNode] = [], isOrphan: Bool = false) {
        self.span = span
        self.children = children
        self.isOrphan = isOrphan
    }
}

public struct TraceSnapshot: Identifiable, Hashable, Sendable {
    public var id: TraceID { traceID }

    public let traceID: TraceID
    public let spans: [SpanSnapshot]

    public init(traceID: TraceID, spans: [SpanSnapshot]) {
        self.traceID = traceID
        self.spans = spans
            .filter { $0.traceID == traceID }
            .sorted(by: Self.spanOrdering)
    }

    public var startTime: TelemetryTimestamp? {
        spans.map(\.startTime).min()
    }

    public var endTime: TelemetryTimestamp? {
        spans.map(\.endTime).max()
    }

    public var containsError: Bool {
        spans.contains { $0.status.isError }
    }

    public var displayName: String {
        roots.first?.span.name ?? spans.first?.name ?? "Empty trace"
    }

    public var roots: [SpanTreeNode] {
        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.spanID, $0) })
        let cyclicIDs = Set(spans.filter { participatesInCycle($0, spansByID: spansByID) }.map(\.spanID))
        var childrenByParent: [SpanID: [SpanSnapshot]] = [:]
        var rootSpans: [(span: SpanSnapshot, orphan: Bool)] = []

        for span in spans {
            guard
                let parentID = span.parentSpanID,
                spansByID[parentID] != nil,
                !cyclicIDs.contains(span.spanID),
                !cyclicIDs.contains(parentID)
            else {
                rootSpans.append((span, span.parentSpanID != nil))
                continue
            }
            childrenByParent[parentID, default: []].append(span)
        }

        func node(for span: SpanSnapshot, orphan: Bool = false) -> SpanTreeNode {
            let children = (childrenByParent[span.spanID] ?? [])
                .sorted(by: Self.spanOrdering)
                .map { node(for: $0) }
            return SpanTreeNode(span: span, children: children, isOrphan: orphan)
        }

        return rootSpans
            .sorted { Self.spanOrdering($0.span, $1.span) }
            .map { node(for: $0.span, orphan: $0.orphan) }
    }

    private func participatesInCycle(
        _ span: SpanSnapshot,
        spansByID: [SpanID: SpanSnapshot]
    ) -> Bool {
        var visited: Set<SpanID> = [span.spanID]
        var parentID = span.parentSpanID
        while let current = parentID, let parent = spansByID[current] {
            guard visited.insert(current).inserted else {
                return true
            }
            parentID = parent.parentSpanID
        }
        return false
    }

    private static func spanOrdering(_ lhs: SpanSnapshot, _ rhs: SpanSnapshot) -> Bool {
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        return lhs.spanID < rhs.spanID
    }
}
