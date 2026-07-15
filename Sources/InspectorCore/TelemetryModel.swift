import Foundation

public struct TraceID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SpanID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TelemetryTimestamp: Hashable, Comparable, Codable, Sendable {
    public let nanosecondsSinceEpoch: UInt64

    public init(nanosecondsSinceEpoch: UInt64) {
        self.nanosecondsSinceEpoch = nanosecondsSinceEpoch
    }

    public init(date: Date) {
        nanosecondsSinceEpoch = UInt64(max(0, date.timeIntervalSince1970) * 1_000_000_000)
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(nanosecondsSinceEpoch) / 1_000_000_000)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanosecondsSinceEpoch < rhs.nanosecondsSinceEpoch
    }
}

public enum TelemetryAttributeValue: Hashable, Codable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case array([TelemetryAttributeValue])
    case dictionary([String: TelemetryAttributeValue])
    case bytes(Data)

    public var displayValue: String {
        switch self {
        case let .string(value):
            value
        case let .bool(value):
            String(value)
        case let .int(value):
            String(value)
        case let .double(value):
            String(value)
        case let .array(values):
            "[\(values.map(\.displayValue).joined(separator: ", "))]"
        case let .dictionary(values):
            "{\(values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.displayValue)" }.joined(separator: ", "))}"
        case let .bytes(value):
            value.base64EncodedString()
        }
    }

    public var estimatedByteCount: Int {
        switch self {
        case let .string(value):
            value.utf8.count
        case .bool:
            MemoryLayout<Bool>.size
        case .int:
            MemoryLayout<Int64>.size
        case .double:
            MemoryLayout<Double>.size
        case let .array(values):
            values.reduce(0) { $0 + $1.estimatedByteCount }
        case let .dictionary(values):
            values.reduce(0) { $0 + $1.key.utf8.count + $1.value.estimatedByteCount }
        case let .bytes(value):
            value.count
        }
    }
}

public enum InspectorSpanKind: Hashable, Codable, Sendable {
    case `internal`
    case server
    case client
    case producer
    case consumer
    case unknown(String)
}

public enum InspectorSpanStatus: Hashable, Codable, Sendable {
    case unset
    case ok
    case error(message: String?)

    public var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

public struct ResourceSnapshot: Hashable, Codable, Sendable {
    public let attributes: [String: TelemetryAttributeValue]
    public let schemaURL: String?

    public init(
        attributes: [String: TelemetryAttributeValue] = [:],
        schemaURL: String? = nil
    ) {
        self.attributes = attributes
        self.schemaURL = schemaURL
    }

    public var serviceName: String? {
        guard case let .string(value) = attributes["service.name"] else {
            return nil
        }
        return value
    }
}

public struct InstrumentationScopeSnapshot: Hashable, Codable, Sendable {
    public let name: String
    public let version: String?
    public let schemaURL: String?
    public let attributes: [String: TelemetryAttributeValue]

    public init(
        name: String,
        version: String? = nil,
        schemaURL: String? = nil,
        attributes: [String: TelemetryAttributeValue] = [:]
    ) {
        self.name = name
        self.version = version
        self.schemaURL = schemaURL
        self.attributes = attributes
    }
}

public struct SpanEventSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let timestamp: TelemetryTimestamp
    public let attributes: [String: TelemetryAttributeValue]
    public let droppedAttributeCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        timestamp: TelemetryTimestamp,
        attributes: [String: TelemetryAttributeValue] = [:],
        droppedAttributeCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.attributes = attributes
        self.droppedAttributeCount = droppedAttributeCount
    }
}

public struct SpanLinkSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let traceID: TraceID
    public let spanID: SpanID
    public let traceState: String?
    public let attributes: [String: TelemetryAttributeValue]
    public let droppedAttributeCount: Int

    public init(
        id: UUID = UUID(),
        traceID: TraceID,
        spanID: SpanID,
        traceState: String? = nil,
        attributes: [String: TelemetryAttributeValue] = [:],
        droppedAttributeCount: Int = 0
    ) {
        self.id = id
        self.traceID = traceID
        self.spanID = spanID
        self.traceState = traceState
        self.attributes = attributes
        self.droppedAttributeCount = droppedAttributeCount
    }
}

public struct SpanSnapshot: Identifiable, Hashable, Codable, Sendable {
    public var id: SpanID { spanID }

    public let traceID: TraceID
    public let spanID: SpanID
    public let parentSpanID: SpanID?
    public let traceState: String?
    public let name: String
    public let kind: InspectorSpanKind
    public let startTime: TelemetryTimestamp
    public let endTime: TelemetryTimestamp
    public let attributes: [String: TelemetryAttributeValue]
    public let events: [SpanEventSnapshot]
    public let links: [SpanLinkSnapshot]
    public let status: InspectorSpanStatus
    public let resource: ResourceSnapshot
    public let instrumentationScope: InstrumentationScopeSnapshot
    public let droppedAttributeCount: Int
    public let droppedEventCount: Int
    public let droppedLinkCount: Int

    public init(
        traceID: TraceID,
        spanID: SpanID,
        parentSpanID: SpanID? = nil,
        traceState: String? = nil,
        name: String,
        kind: InspectorSpanKind = .internal,
        startTime: TelemetryTimestamp,
        endTime: TelemetryTimestamp,
        attributes: [String: TelemetryAttributeValue] = [:],
        events: [SpanEventSnapshot] = [],
        links: [SpanLinkSnapshot] = [],
        status: InspectorSpanStatus = .unset,
        resource: ResourceSnapshot = ResourceSnapshot(),
        instrumentationScope: InstrumentationScopeSnapshot = InstrumentationScopeSnapshot(name: ""),
        droppedAttributeCount: Int = 0,
        droppedEventCount: Int = 0,
        droppedLinkCount: Int = 0
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.traceState = traceState
        self.name = name
        self.kind = kind
        self.startTime = startTime
        self.endTime = endTime
        self.attributes = attributes
        self.events = events
        self.links = links
        self.status = status
        self.resource = resource
        self.instrumentationScope = instrumentationScope
        self.droppedAttributeCount = droppedAttributeCount
        self.droppedEventCount = droppedEventCount
        self.droppedLinkCount = droppedLinkCount
    }

    public var durationNanoseconds: UInt64 {
        endTime.nanosecondsSinceEpoch >= startTime.nanosecondsSinceEpoch
            ? endTime.nanosecondsSinceEpoch - startTime.nanosecondsSinceEpoch
            : 0
    }

    public var estimatedByteCount: Int {
        var count = 256
        count += traceID.rawValue.utf8.count + spanID.rawValue.utf8.count
        count += parentSpanID?.rawValue.utf8.count ?? 0
        count += traceState?.utf8.count ?? 0
        count += name.utf8.count
        count += Self.estimatedByteCount(of: attributes)
        count += Self.estimatedByteCount(of: resource.attributes)
        count += Self.estimatedByteCount(of: instrumentationScope.attributes)
        count += events.reduce(0) {
            $0 + $1.name.utf8.count + Self.estimatedByteCount(of: $1.attributes)
        }
        count += links.reduce(0) {
            $0 + $1.traceID.rawValue.utf8.count + $1.spanID.rawValue.utf8.count
                + Self.estimatedByteCount(of: $1.attributes)
        }
        return count
    }

    private static func estimatedByteCount(
        of attributes: [String: TelemetryAttributeValue]
    ) -> Int {
        attributes.reduce(0) { $0 + $1.key.utf8.count + $1.value.estimatedByteCount }
    }
}
