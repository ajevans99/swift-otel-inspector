import Foundation

public enum MetricAggregationTemporality: String, Hashable, Codable, Sendable {
    case cumulative
    case delta
}

public enum MetricKind: Hashable, Codable, Sendable {
    case gauge
    case sum(monotonic: Bool)
    case summary
    case histogram
    case exponentialHistogram
}

public enum MetricNumber: Hashable, Codable, Sendable {
    case integer(Int64)
    case double(Double)

    public var doubleValue: Double {
        switch self {
        case let .integer(value):
            Double(value)
        case let .double(value):
            value
        }
    }
}

public struct MetricID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MetricSeriesID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MetricExemplarSnapshot: Hashable, Codable, Sendable {
    public let timestamp: TelemetryTimestamp
    public let value: MetricNumber
    public let filteredAttributes: [String: TelemetryAttributeValue]
    public let traceID: TraceID?
    public let spanID: SpanID?

    public init(
        timestamp: TelemetryTimestamp,
        value: MetricNumber,
        filteredAttributes: [String: TelemetryAttributeValue] = [:],
        traceID: TraceID? = nil,
        spanID: SpanID? = nil
    ) {
        self.timestamp = timestamp
        self.value = value
        self.filteredAttributes = filteredAttributes
        self.traceID = traceID
        self.spanID = spanID
    }
}

public struct MetricHistogramSnapshot: Hashable, Codable, Sendable {
    public let count: UInt64
    public let sum: Double
    public let minimum: Double?
    public let maximum: Double?
    public let boundaries: [Double]
    public let bucketCounts: [UInt64]

    public init(
        count: UInt64,
        sum: Double,
        minimum: Double? = nil,
        maximum: Double? = nil,
        boundaries: [Double],
        bucketCounts: [UInt64]
    ) {
        self.count = count
        self.sum = sum
        self.minimum = minimum
        self.maximum = maximum
        self.boundaries = boundaries
        self.bucketCounts = bucketCounts
    }
}

public struct MetricExponentialBucketsSnapshot: Hashable, Codable, Sendable {
    public let offset: Int
    public let bucketCounts: [UInt64]

    public init(offset: Int, bucketCounts: [UInt64]) {
        self.offset = offset
        self.bucketCounts = bucketCounts
    }
}

public struct MetricExponentialHistogramSnapshot: Hashable, Codable, Sendable {
    public let count: UInt64
    public let sum: Double
    public let minimum: Double?
    public let maximum: Double?
    public let scale: Int
    public let zeroCount: UInt64
    public let positive: MetricExponentialBucketsSnapshot
    public let negative: MetricExponentialBucketsSnapshot

    public init(
        count: UInt64,
        sum: Double,
        minimum: Double? = nil,
        maximum: Double? = nil,
        scale: Int,
        zeroCount: UInt64,
        positive: MetricExponentialBucketsSnapshot,
        negative: MetricExponentialBucketsSnapshot
    ) {
        self.count = count
        self.sum = sum
        self.minimum = minimum
        self.maximum = maximum
        self.scale = scale
        self.zeroCount = zeroCount
        self.positive = positive
        self.negative = negative
    }
}

public struct MetricQuantileSnapshot: Hashable, Codable, Sendable {
    public let quantile: Double
    public let value: Double

    public init(quantile: Double, value: Double) {
        self.quantile = quantile
        self.value = value
    }
}

public struct MetricSummarySnapshot: Hashable, Codable, Sendable {
    public let count: UInt64
    public let sum: Double
    public let quantiles: [MetricQuantileSnapshot]

    public init(count: UInt64, sum: Double, quantiles: [MetricQuantileSnapshot]) {
        self.count = count
        self.sum = sum
        self.quantiles = quantiles
    }
}

public enum MetricPointValue: Hashable, Codable, Sendable {
    case number(MetricNumber)
    case histogram(MetricHistogramSnapshot)
    case exponentialHistogram(MetricExponentialHistogramSnapshot)
    case summary(MetricSummarySnapshot)
}

public struct MetricPointSnapshot: Hashable, Codable, Sendable {
    public let startTime: TelemetryTimestamp
    public let endTime: TelemetryTimestamp
    public let value: MetricPointValue
    public let exemplars: [MetricExemplarSnapshot]

    public init(
        startTime: TelemetryTimestamp,
        endTime: TelemetryTimestamp,
        value: MetricPointValue,
        exemplars: [MetricExemplarSnapshot] = []
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.value = value
        self.exemplars = exemplars
    }
}

public struct MetricSeriesSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: MetricSeriesID
    public let attributes: [String: TelemetryAttributeValue]
    public let points: [MetricPointSnapshot]

    public init(
        id: MetricSeriesID? = nil,
        attributes: [String: TelemetryAttributeValue] = [:],
        points: [MetricPointSnapshot]
    ) {
        self.id = id ?? MetricSeriesID(rawValue: attributes.metricCanonicalValue)
        self.attributes = attributes
        self.points = points
    }
}

public struct MetricSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: MetricID
    public let name: String
    public let description: String
    public let unit: String
    public let kind: MetricKind
    public let temporality: MetricAggregationTemporality
    public let resource: ResourceSnapshot
    public let instrumentationScope: InstrumentationScopeSnapshot
    public let series: [MetricSeriesSnapshot]

    public init(
        id: MetricID? = nil,
        name: String,
        description: String = "",
        unit: String = "",
        kind: MetricKind,
        temporality: MetricAggregationTemporality,
        resource: ResourceSnapshot = ResourceSnapshot(),
        instrumentationScope: InstrumentationScopeSnapshot = InstrumentationScopeSnapshot(name: ""),
        series: [MetricSeriesSnapshot]
    ) {
        self.id = id ?? MetricID(
            rawValue: Self.canonicalID(
                name: name,
                kind: kind,
                resource: resource,
                instrumentationScope: instrumentationScope
            )
        )
        self.name = name
        self.description = description
        self.unit = unit
        self.kind = kind
        self.temporality = temporality
        self.resource = resource
        self.instrumentationScope = instrumentationScope
        self.series = series
    }

    public var latestTimestamp: TelemetryTimestamp? {
        series.flatMap(\.points).map(\.endTime).max()
    }

    private static func canonicalID(
        name: String,
        kind: MetricKind,
        resource: ResourceSnapshot,
        instrumentationScope: InstrumentationScopeSnapshot
    ) -> String {
        [
            name.metricLengthPrefixed,
            kind.metricCanonicalValue.metricLengthPrefixed,
            resource.attributes.metricCanonicalValue.metricLengthPrefixed,
            instrumentationScope.name.metricLengthPrefixed,
            (instrumentationScope.version ?? "").metricLengthPrefixed,
            instrumentationScope.attributes.metricCanonicalValue.metricLengthPrefixed,
        ].joined(separator: "|")
    }
}

private extension MetricKind {
    var metricCanonicalValue: String {
        switch self {
        case .gauge:
            "gauge"
        case let .sum(monotonic):
            monotonic ? "sum:monotonic" : "sum:nonmonotonic"
        case .summary:
            "summary"
        case .histogram:
            "histogram"
        case .exponentialHistogram:
            "exponentialHistogram"
        }
    }
}

extension Dictionary where Key == String, Value == TelemetryAttributeValue {
    var metricCanonicalValue: String {
        sorted(by: { $0.key < $1.key }).map {
            $0.key.metricLengthPrefixed + $0.value.metricCanonicalValue.metricLengthPrefixed
        }.joined()
    }
}

private extension TelemetryAttributeValue {
    var metricCanonicalValue: String {
        switch self {
        case let .string(value):
            "s" + value.metricLengthPrefixed
        case let .bool(value):
            value ? "b1" : "b0"
        case let .int(value):
            "i\(value)"
        case let .double(value):
            "d\(value.bitPattern)"
        case let .array(values):
            "a" + values.map { $0.metricCanonicalValue.metricLengthPrefixed }.joined()
        case let .dictionary(values):
            "k" + values.metricCanonicalValue
        case let .bytes(values):
            "x" + values.base64EncodedString().metricLengthPrefixed
        }
    }
}

private extension String {
    var metricLengthPrefixed: String {
        "\(utf8.count):\(self)"
    }
}
