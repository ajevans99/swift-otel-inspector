import InspectorCore
import InspectorSwiftUI
import Testing

@Test @MainActor
func logModelFiltersSeverityServiceCorrelationAndContent() async {
    let store = LogStore(clock: { TelemetryTimestamp(nanosecondsSinceEpoch: 100) })
    let model = LogInspectorModel(store: store)
    await store.insert([
        testLog(
            id: 1,
            message: "request succeeded",
            service: "api",
            severity: .info,
            correlated: true
        ),
        testLog(
            id: 2,
            message: "database timeout",
            service: "worker",
            severity: .error,
            correlated: false
        ),
    ])
    for _ in 0 ..< 20 where model.logs.count < 2 {
        try? await Task.sleep(for: .milliseconds(5))
    }

    model.severityFilter = .error
    model.selectedService = "worker"
    model.searchText = "TIMEOUT"
    #expect(model.filteredLogs.map(\.message) == ["database timeout"])

    model.correlatedOnly = true
    #expect(model.filteredLogs.isEmpty)
}

@Test
func traceTimelineInterleavesSpansEventsAndCorrelatedLogs() {
    let traceID = TraceID(rawValue: "trace")
    let span = SpanSnapshot(
        traceID: traceID,
        spanID: SpanID(rawValue: "span"),
        name: "request",
        startTime: TelemetryTimestamp(nanosecondsSinceEpoch: 10),
        endTime: TelemetryTimestamp(nanosecondsSinceEpoch: 40),
        events: [
            SpanEventSnapshot(
                name: "retry",
                timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: 30)
            ),
        ]
    )
    let correlated = LogSnapshot(
        timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: 20),
        traceID: traceID,
        spanID: span.spanID,
        severity: .warning,
        body: .string("slow")
    )
    let unrelated = LogSnapshot(
        timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: 25),
        traceID: TraceID(rawValue: "other"),
        body: .string("ignore")
    )

    let items = TraceTimelineItem.items(
        for: TraceSnapshot(traceID: traceID, spans: [span]),
        logs: [unrelated, correlated]
    )

    #expect(items.map(\.timestamp.nanosecondsSinceEpoch) == [10, 20, 30, 40])
    #expect(items.map(\.title) == ["request", "slow", "retry", "request"])
}

private func testLog(
    id: UInt64,
    message: String,
    service: String,
    severity: LogSeverity,
    correlated: Bool
) -> LogSnapshot {
    LogSnapshot(
        timestamp: TelemetryTimestamp(nanosecondsSinceEpoch: id),
        traceID: correlated ? TraceID(rawValue: "trace") : nil,
        severity: severity,
        body: .string(message),
        attributes: ["component": .string("network")],
        resource: ResourceSnapshot(attributes: ["service.name": .string(service)])
    )
}
