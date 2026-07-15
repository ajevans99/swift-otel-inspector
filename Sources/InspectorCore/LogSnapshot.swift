import Foundation

public struct LogSeverity: Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int
    public let text: String

    public init(rawValue: Int, text: String) {
        self.rawValue = rawValue
        self.text = text
    }

    public static let trace = LogSeverity(rawValue: 1, text: "TRACE")
    public static let debug = LogSeverity(rawValue: 5, text: "DEBUG")
    public static let info = LogSeverity(rawValue: 9, text: "INFO")
    public static let warning = LogSeverity(rawValue: 13, text: "WARN")
    public static let error = LogSeverity(rawValue: 17, text: "ERROR")
    public static let fatal = LogSeverity(rawValue: 21, text: "FATAL")

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LogSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: TelemetryTimestamp
    public let observedTimestamp: TelemetryTimestamp?
    public let traceID: TraceID?
    public let spanID: SpanID?
    public let severity: LogSeverity?
    public let body: TelemetryAttributeValue?
    public let eventName: String?
    public let attributes: [String: TelemetryAttributeValue]
    public let resource: ResourceSnapshot
    public let instrumentationScope: InstrumentationScopeSnapshot

    public init(
        id: UUID = UUID(),
        timestamp: TelemetryTimestamp,
        observedTimestamp: TelemetryTimestamp? = nil,
        traceID: TraceID? = nil,
        spanID: SpanID? = nil,
        severity: LogSeverity? = nil,
        body: TelemetryAttributeValue? = nil,
        eventName: String? = nil,
        attributes: [String: TelemetryAttributeValue] = [:],
        resource: ResourceSnapshot = ResourceSnapshot(),
        instrumentationScope: InstrumentationScopeSnapshot = InstrumentationScopeSnapshot(name: "")
    ) {
        self.id = id
        self.timestamp = timestamp
        self.observedTimestamp = observedTimestamp
        self.traceID = traceID
        self.spanID = spanID
        self.severity = severity
        self.body = body
        self.eventName = eventName
        self.attributes = attributes
        self.resource = resource
        self.instrumentationScope = instrumentationScope
    }

    public var message: String {
        body?.displayValue ?? eventName ?? "(empty log)"
    }

    public var estimatedByteCount: Int {
        var count = 192
        count += traceID?.rawValue.utf8.count ?? 0
        count += spanID?.rawValue.utf8.count ?? 0
        count += severity?.text.utf8.count ?? 0
        count += body?.estimatedByteCount ?? 0
        count += eventName?.utf8.count ?? 0
        count += attributes.estimatedByteCount
        count += resource.attributes.estimatedByteCount
        count += instrumentationScope.attributes.estimatedByteCount
        return count
    }
}

extension Dictionary where Key == String, Value == TelemetryAttributeValue {
    var estimatedByteCount: Int {
        reduce(0) { $0 + $1.key.utf8.count + $1.value.estimatedByteCount }
    }
}
