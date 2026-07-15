import InspectorCore

public struct SpanWaterfallItem: Identifiable, Equatable, Sendable {
    public var id: SpanID { span.spanID }

    public let span: SpanSnapshot
    public let depth: Int
    public let offsetFraction: Double
    public let widthFraction: Double

    public init(
        span: SpanSnapshot,
        depth: Int,
        offsetFraction: Double,
        widthFraction: Double
    ) {
        self.span = span
        self.depth = depth
        self.offsetFraction = offsetFraction
        self.widthFraction = widthFraction
    }
}

public enum SpanWaterfallLayout {
    public static func items(for trace: TraceSnapshot) -> [SpanWaterfallItem] {
        guard
            let traceStart = trace.startTime?.nanosecondsSinceEpoch,
            let traceEnd = trace.endTime?.nanosecondsSinceEpoch
        else {
            return []
        }
        let traceDuration = max(1, traceEnd >= traceStart ? traceEnd - traceStart : 0)

        func flatten(_ node: SpanTreeNode, depth: Int) -> [SpanWaterfallItem] {
            let start = node.span.startTime.nanosecondsSinceEpoch
            let offset = start >= traceStart ? start - traceStart : 0
            let item = SpanWaterfallItem(
                span: node.span,
                depth: depth,
                offsetFraction: min(1, Double(offset) / Double(traceDuration)),
                widthFraction: max(
                    0.003,
                    min(1, Double(node.span.durationNanoseconds) / Double(traceDuration))
                )
            )
            return [item] + node.children.flatMap { flatten($0, depth: depth + 1) }
        }

        return trace.roots.flatMap { flatten($0, depth: 0) }
    }
}
