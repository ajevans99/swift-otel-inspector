import Foundation

extension TelemetryAttributeValue {
    func truncated(to maximumBytes: Int) -> TelemetryAttributeValue {
        switch self {
        case let .string(value):
            .string(value.truncatedUTF8(to: maximumBytes))
        case let .array(values):
            .array(values.map { $0.truncated(to: maximumBytes) })
        case let .dictionary(values):
            .dictionary(values.mapValues { $0.truncated(to: maximumBytes) })
        case let .bytes(value):
            .bytes(Data(value.prefix(maximumBytes)))
        case .bool, .int, .double:
            self
        }
    }
}

private extension String {
    func truncatedUTF8(to maximumBytes: Int) -> String {
        guard utf8.count > maximumBytes else {
            return self
        }

        var end = utf8.index(utf8.startIndex, offsetBy: maximumBytes)
        while end > utf8.startIndex {
            if let result = String(bytes: utf8[..<end], encoding: .utf8) {
                return result
            }
            end = utf8.index(before: end)
        }
        return ""
    }
}
