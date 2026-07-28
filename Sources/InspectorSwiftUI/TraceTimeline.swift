#if !os(watchOS)

import InspectorCore

public struct TraceTimelineItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case spanStarted
        case spanEnded
        case spanEvent
        case log(LogSeverity?)
    }

    public let id: String
    public let timestamp: TelemetryTimestamp
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let spanID: SpanID?

    public static func items(
        for trace: TraceSnapshot,
        logs: [LogSnapshot]
    ) -> [TraceTimelineItem] {
        let spanItems = trace.spans.flatMap { span in
            [
                TraceTimelineItem(
                    id: "span-start-\(span.spanID.rawValue)",
                    timestamp: span.startTime,
                    kind: .spanStarted,
                    title: span.name,
                    subtitle: "\(span.resource.serviceName ?? "unknown service") started",
                    spanID: span.spanID
                ),
                TraceTimelineItem(
                    id: "span-end-\(span.spanID.rawValue)",
                    timestamp: span.endTime,
                    kind: .spanEnded,
                    title: span.name,
                    subtitle: span.status.isError ? "Ended with error" : "Ended",
                    spanID: span.spanID
                ),
            ] + span.events.enumerated().map { index, event in
                TraceTimelineItem(
                    id: "event-\(span.spanID.rawValue)-\(index)",
                    timestamp: event.timestamp,
                    kind: .spanEvent,
                    title: event.name,
                    subtitle: span.name,
                    spanID: span.spanID
                )
            }
        }
        let logItems = logs
            .filter { $0.traceID == trace.traceID }
            .map { log in
                TraceTimelineItem(
                    id: "log-\(log.id)",
                    timestamp: log.timestamp,
                    kind: .log(log.severity),
                    title: log.message,
                    subtitle: "\(log.resource.serviceName ?? "unknown service") log",
                    spanID: log.spanID
                )
            }

        return (spanItems + logItems).sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id < $1.id
            }
            return $0.timestamp < $1.timestamp
        }
    }
}


#endif
