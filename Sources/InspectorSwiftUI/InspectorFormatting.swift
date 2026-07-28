#if !os(watchOS)

import Foundation
import InspectorCore

public enum InspectorFormatting {
    public static func duration(_ nanoseconds: UInt64) -> String {
        switch nanoseconds {
        case 0 ..< 1_000:
            return "\(nanoseconds) ns"
        case 1_000 ..< 1_000_000:
            return String(format: "%.2f us", Double(nanoseconds) / 1_000)
        case 1_000_000 ..< 1_000_000_000:
            return String(format: "%.2f ms", Double(nanoseconds) / 1_000_000)
        default:
            return String(format: "%.2f s", Double(nanoseconds) / 1_000_000_000)
        }
    }

    public static func timestamp(_ timestamp: TelemetryTimestamp) -> String {
        timestamp.date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .second()
                .secondFraction(.fractional(3))
        )
    }

    public static func status(_ status: InspectorSpanStatus) -> String {
        switch status {
        case .unset:
            "Unset"
        case .ok:
            "OK"
        case let .error(message):
            message.map { "Error: \($0)" } ?? "Error"
        }
    }

    public static func kind(_ kind: InspectorSpanKind) -> String {
        switch kind {
        case .internal:
            "Internal"
        case .server:
            "Server"
        case .client:
            "Client"
        case .producer:
            "Producer"
        case .consumer:
            "Consumer"
        case let .unknown(value):
            value
        }
    }
}


#endif
