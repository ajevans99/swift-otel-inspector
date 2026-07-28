#if !os(watchOS)

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

    static func decodeMetrics(_ data: Data) throws -> [MetricSnapshot] {
        let request = try JSONDecoder().decode(ExportMetricsRequest.self, from: data)
        return request.resourceMetrics.flatMap { resourceMetrics in
            let resource = ResourceSnapshot(
                attributes: attributes(resourceMetrics.resource.attributes),
                schemaURL: resourceMetrics.schemaUrl
            )
            return resourceMetrics.scopeMetrics.flatMap { scopeMetrics in
                let scope = InstrumentationScopeSnapshot(
                    name: scopeMetrics.scope.name,
                    version: scopeMetrics.scope.version,
                    schemaURL: scopeMetrics.schemaUrl
                )
                return scopeMetrics.metrics.compactMap {
                    metricSnapshot($0, resource: resource, scope: scope)
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

    private static func metricSnapshot(
        _ metric: OTLPMetric,
        resource: ResourceSnapshot,
        scope: InstrumentationScopeSnapshot
    ) -> MetricSnapshot? {
        if let gauge = metric.gauge {
            return numberMetric(
                metric,
                points: gauge.dataPoints,
                kind: .gauge,
                temporality: .cumulative,
                resource: resource,
                scope: scope
            )
        }
        if let sum = metric.sum {
            return numberMetric(
                metric,
                points: sum.dataPoints,
                kind: .sum(monotonic: sum.isMonotonic),
                temporality: temporality(sum.aggregationTemporality),
                resource: resource,
                scope: scope
            )
        }
        if let histogram = metric.histogram {
            let series = histogram.dataPoints.map {
                MetricSeriesSnapshot(
                    attributes: attributes($0.attributes ?? []),
                    points: [
                        MetricPointSnapshot(
                            startTime: timestamp($0.startTimeUnixNano ?? "0"),
                            endTime: timestamp($0.timeUnixNano),
                            value: .histogram(
                                MetricHistogramSnapshot(
                                    count: UInt64($0.count) ?? 0,
                                    sum: $0.sum ?? 0,
                                    minimum: $0.min,
                                    maximum: $0.max,
                                    boundaries: $0.explicitBounds,
                                    bucketCounts: $0.bucketCounts.map { UInt64($0) ?? 0 }
                                )
                            ),
                            exemplars: ($0.exemplars ?? []).compactMap(exemplar)
                        ),
                    ]
                )
            }
            return MetricSnapshot(
                name: metric.name,
                description: metric.description ?? "",
                unit: metric.unit ?? "",
                kind: .histogram,
                temporality: temporality(histogram.aggregationTemporality),
                resource: resource,
                instrumentationScope: scope,
                series: series
            )
        }
        return nil
    }

    private static func numberMetric(
        _ metric: OTLPMetric,
        points: [OTLPNumberDataPoint],
        kind: MetricKind,
        temporality: MetricAggregationTemporality,
        resource: ResourceSnapshot,
        scope: InstrumentationScopeSnapshot
    ) -> MetricSnapshot {
        MetricSnapshot(
            name: metric.name,
            description: metric.description ?? "",
            unit: metric.unit ?? "",
            kind: kind,
            temporality: temporality,
            resource: resource,
            instrumentationScope: scope,
            series: points.compactMap { point in
                guard let value = point.metricNumber else {
                    return nil
                }
                return MetricSeriesSnapshot(
                    attributes: attributes(point.attributes ?? []),
                    points: [
                        MetricPointSnapshot(
                            startTime: timestamp(point.startTimeUnixNano ?? "0"),
                            endTime: timestamp(point.timeUnixNano),
                            value: .number(value),
                            exemplars: (point.exemplars ?? []).compactMap(exemplar)
                        ),
                    ]
                )
            }
        )
    }

    private static func exemplar(_ exemplar: OTLPExemplar) -> MetricExemplarSnapshot? {
        guard let value = exemplar.metricNumber else {
            return nil
        }
        return MetricExemplarSnapshot(
            timestamp: timestamp(exemplar.timeUnixNano),
            value: value,
            filteredAttributes: attributes(exemplar.filteredAttributes ?? []),
            traceID: exemplar.traceId.map(TraceID.init),
            spanID: exemplar.spanId.map(SpanID.init)
        )
    }

    private static func temporality(_ value: Int) -> MetricAggregationTemporality {
        value == 1 ? .delta : .cumulative
    }

    private static func attributes(
        _ keyValues: [KeyValue]
    ) -> [String: TelemetryAttributeValue] {
        Dictionary(uniqueKeysWithValues: keyValues.compactMap { entry in
            entry.value.attributeValue.map { (entry.key, $0) }
        })
    }

    private struct ExportMetricsRequest: Decodable {
        let resourceMetrics: [OTLPResourceMetrics]
    }

    private struct OTLPResourceMetrics: Decodable {
        let resource: OTLPResource
        let scopeMetrics: [OTLPScopeMetrics]
        let schemaUrl: String?
    }

    private struct OTLPScopeMetrics: Decodable {
        let scope: OTLPScope
        let metrics: [OTLPMetric]
        let schemaUrl: String?
    }

    private struct OTLPMetric: Decodable {
        let name: String
        let description: String?
        let unit: String?
        let gauge: OTLPNumberData?
        let sum: OTLPSumData?
        let histogram: OTLPHistogramData?
    }

    private struct OTLPNumberData: Decodable {
        let dataPoints: [OTLPNumberDataPoint]
    }

    private struct OTLPSumData: Decodable {
        let dataPoints: [OTLPNumberDataPoint]
        let aggregationTemporality: Int
        let isMonotonic: Bool
    }

    private struct OTLPNumberDataPoint: Decodable {
        let startTimeUnixNano: String?
        let timeUnixNano: String
        let asInt: String?
        let asDouble: Double?
        let attributes: [KeyValue]?
        let exemplars: [OTLPExemplar]?

        var metricNumber: MetricNumber? {
            if let asInt, let value = Int64(asInt) {
                return .integer(value)
            }
            return asDouble.map(MetricNumber.double)
        }
    }

    private struct OTLPHistogramData: Decodable {
        let aggregationTemporality: Int
        let dataPoints: [OTLPHistogramDataPoint]
    }

    private struct OTLPHistogramDataPoint: Decodable {
        let startTimeUnixNano: String?
        let timeUnixNano: String
        let count: String
        let sum: Double?
        let min: Double?
        let max: Double?
        let explicitBounds: [Double]
        let bucketCounts: [String]
        let attributes: [KeyValue]?
        let exemplars: [OTLPExemplar]?
    }

    private struct OTLPExemplar: Decodable {
        let timeUnixNano: String
        let asInt: String?
        let asDouble: Double?
        let filteredAttributes: [KeyValue]?
        let traceId: String?
        let spanId: String?

        var metricNumber: MetricNumber? {
            if let asInt, let value = Int64(asInt) {
                return .integer(value)
            }
            return asDouble.map(MetricNumber.double)
        }
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


#endif
