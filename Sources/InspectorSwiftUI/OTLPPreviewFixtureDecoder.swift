#if DEBUG
import Foundation
import InspectorCore

enum OTLPPreviewFixtureDecoder {
    static func decode(_ data: Data) throws -> [SpanSnapshot] {
        let request = try JSONDecoder().decode(ExportRequest.self, from: data)
        return request.resourceSpans.flatMap { resourceSpans in
            let resource = ResourceSnapshot(
                attributes: attributes(resourceSpans.resource.attributes),
                schemaURL: resourceSpans.schemaUrl
            )
            return resourceSpans.scopeSpans.flatMap { scopeSpans in
                let scope = InstrumentationScopeSnapshot(
                    name: scopeSpans.scope.name,
                    version: scopeSpans.scope.version,
                    schemaURL: scopeSpans.schemaUrl
                )
                return scopeSpans.spans.map {
                    snapshot($0, resource: resource, scope: scope)
                }
            }
        }
    }

    private static func snapshot(
        _ span: OTLPSpan,
        resource: ResourceSnapshot,
        scope: InstrumentationScopeSnapshot
    ) -> SpanSnapshot {
        SpanSnapshot(
            traceID: TraceID(rawValue: span.traceId),
            spanID: SpanID(rawValue: span.spanId),
            parentSpanID: span.parentSpanId.map { SpanID(rawValue: $0) },
            traceState: span.traceState,
            name: span.name,
            kind: kind(span.kind),
            startTime: timestamp(span.startTimeUnixNano),
            endTime: timestamp(span.endTimeUnixNano),
            attributes: attributes(span.attributes ?? []),
            events: (span.events ?? []).map {
                SpanEventSnapshot(
                    name: $0.name,
                    timestamp: timestamp($0.timeUnixNano),
                    attributes: attributes($0.attributes ?? []),
                    droppedAttributeCount: $0.droppedAttributesCount ?? 0
                )
            },
            links: (span.links ?? []).map {
                SpanLinkSnapshot(
                    traceID: TraceID(rawValue: $0.traceId),
                    spanID: SpanID(rawValue: $0.spanId),
                    traceState: $0.traceState,
                    attributes: attributes($0.attributes ?? []),
                    droppedAttributeCount: $0.droppedAttributesCount ?? 0
                )
            },
            status: status(span.status),
            resource: resource,
            instrumentationScope: scope,
            droppedAttributeCount: span.droppedAttributesCount ?? 0,
            droppedEventCount: span.droppedEventsCount ?? 0,
            droppedLinkCount: span.droppedLinksCount ?? 0
        )
    }

    private static func attributes(
        _ keyValues: [KeyValue]
    ) -> [String: TelemetryAttributeValue] {
        Dictionary(uniqueKeysWithValues: keyValues.compactMap { entry in
            entry.value.attributeValue.map { (entry.key, $0) }
        })
    }

    private static func timestamp(_ value: String) -> TelemetryTimestamp {
        TelemetryTimestamp(nanosecondsSinceEpoch: UInt64(value) ?? 0)
    }

    private static func kind(_ value: Int) -> InspectorSpanKind {
        switch value {
        case 1: .internal
        case 2: .server
        case 3: .client
        case 4: .producer
        case 5: .consumer
        default: .unknown("OTLP kind \(value)")
        }
    }

    private static func status(_ value: OTLPStatus?) -> InspectorSpanStatus {
        switch value?.code ?? 0 {
        case 1:
            .ok
        case 2:
            .error(message: value?.message)
        default:
            .unset
        }
    }
}

private struct ExportRequest: Decodable {
    let resourceSpans: [ResourceSpans]
}

private struct ResourceSpans: Decodable {
    let resource: OTLPResource
    let scopeSpans: [ScopeSpans]
    let schemaUrl: String?
}

private struct OTLPResource: Decodable {
    let attributes: [KeyValue]
}

private struct ScopeSpans: Decodable {
    let scope: OTLPScope
    let spans: [OTLPSpan]
    let schemaUrl: String?
}

private struct OTLPScope: Decodable {
    let name: String
    let version: String?
}

private struct OTLPSpan: Decodable {
    let traceId: String
    let spanId: String
    let parentSpanId: String?
    let traceState: String?
    let name: String
    let kind: Int
    let startTimeUnixNano: String
    let endTimeUnixNano: String
    let attributes: [KeyValue]?
    let events: [OTLPEvent]?
    let links: [OTLPLink]?
    let status: OTLPStatus?
    let droppedAttributesCount: Int?
    let droppedEventsCount: Int?
    let droppedLinksCount: Int?
}

private struct OTLPEvent: Decodable {
    let timeUnixNano: String
    let name: String
    let attributes: [KeyValue]?
    let droppedAttributesCount: Int?
}

private struct OTLPLink: Decodable {
    let traceId: String
    let spanId: String
    let traceState: String?
    let attributes: [KeyValue]?
    let droppedAttributesCount: Int?
}

private struct OTLPStatus: Decodable {
    let message: String?
    let code: Int
}

private struct KeyValue: Decodable {
    let key: String
    let value: AnyValue
}

private struct AnyValue: Decodable {
    let stringValue: String?
    let boolValue: Bool?
    let intValue: String?
    let doubleValue: Double?
    let arrayValue: ArrayValue?
    let kvlistValue: KeyValueList?
    let bytesValue: String?

    var attributeValue: TelemetryAttributeValue? {
        if let stringValue {
            return .string(stringValue)
        }
        if let boolValue {
            return .bool(boolValue)
        }
        if let intValue, let value = Int64(intValue) {
            return .int(value)
        }
        if let doubleValue {
            return .double(doubleValue)
        }
        if let arrayValue {
            return .array(arrayValue.values.compactMap(\.attributeValue))
        }
        if let kvlistValue {
            return .dictionary(
                Dictionary(uniqueKeysWithValues: kvlistValue.values.compactMap { entry in
                    entry.value.attributeValue.map { (entry.key, $0) }
                })
            )
        }
        if let bytesValue, let data = Data(base64Encoded: bytesValue) {
            return .bytes(data)
        }
        return nil
    }
}

private struct ArrayValue: Decodable {
    let values: [AnyValue]
}

private struct KeyValueList: Decodable {
    let values: [KeyValue]
}
#endif
