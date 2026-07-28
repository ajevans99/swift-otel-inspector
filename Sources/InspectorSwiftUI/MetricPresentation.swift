#if !os(watchOS)

import Foundation
import InspectorCore

public struct MetricChartSample: Identifiable, Hashable, Sendable {
    public let timestamp: TelemetryTimestamp
    public let value: Double
    public let isReset: Bool

    public var id: UInt64 {
        timestamp.nanosecondsSinceEpoch
    }

    public init(timestamp: TelemetryTimestamp, value: Double, isReset: Bool = false) {
        self.timestamp = timestamp
        self.value = value
        self.isReset = isReset
    }
}

public struct MetricHistogramBucket: Identifiable, Hashable, Sendable {
    public let index: Int
    public let label: String
    public let count: UInt64

    public var id: Int { index }

    public init(index: Int, label: String, count: UInt64) {
        self.index = index
        self.label = label
        self.count = count
    }
}

public enum MetricPresentation {
    public static func chartSamples(
        metric: MetricSnapshot,
        series: MetricSeriesSnapshot
    ) -> [MetricChartSample] {
        let numberPoints = series.points.compactMap { point -> (MetricPointSnapshot, MetricNumber)? in
            guard case let .number(number) = point.value else {
                return nil
            }
            return (point, number)
        }
        switch metric.kind {
        case .gauge, .sum(monotonic: false):
            return numberPoints.map {
                MetricChartSample(timestamp: $0.0.endTime, value: $0.1.doubleValue)
            }
        case .sum(monotonic: true):
            return metric.temporality == .delta
                ? deltaRates(numberPoints)
                : cumulativeRates(numberPoints)
        case .summary, .histogram, .exponentialHistogram:
            return []
        }
    }

    public static func explicitHistogramBuckets(
        _ histogram: MetricHistogramSnapshot
    ) -> [MetricHistogramBucket] {
        histogram.bucketCounts.enumerated().map { index, count in
            let label: String
            if index == 0 {
                label = "<= \(formatBoundary(histogram.boundaries.first))"
            } else if index <= histogram.boundaries.count - 1 {
                label = "\(formatBoundary(histogram.boundaries[index - 1]))-\(formatBoundary(histogram.boundaries[index]))"
            } else {
                label = "> \(formatBoundary(histogram.boundaries.last))"
            }
            return MetricHistogramBucket(index: index, label: label, count: count)
        }
    }

    public static func exponentialHistogramBuckets(
        _ histogram: MetricExponentialHistogramSnapshot
    ) -> [MetricHistogramBucket] {
        let negative = histogram.negative.bucketCounts.enumerated().map {
            MetricHistogramBucket(
                index: $0.offset,
                label: "neg \($0.offset + histogram.negative.offset)",
                count: $0.element
            )
        }
        let zero = MetricHistogramBucket(
            index: negative.count,
            label: "zero",
            count: histogram.zeroCount
        )
        let positive = histogram.positive.bucketCounts.enumerated().map {
            MetricHistogramBucket(
                index: negative.count + 1 + $0.offset,
                label: "pos \($0.offset + histogram.positive.offset)",
                count: $0.element
            )
        }
        return negative + [zero] + positive
    }

    public static func latestPoint(in series: MetricSeriesSnapshot) -> MetricPointSnapshot? {
        series.points.last
    }

    public static func seriesLabel(_ series: MetricSeriesSnapshot) -> String {
        guard !series.attributes.isEmpty else {
            return "Default series"
        }
        return series.attributes.sorted(by: { $0.key < $1.key })
            .prefix(2)
            .map { "\($0.key)=\($0.value.displayValue)" }
            .joined(separator: ", ")
    }

    private static func cumulativeRates(
        _ points: [(MetricPointSnapshot, MetricNumber)]
    ) -> [MetricChartSample] {
        zip(points, points.dropFirst()).compactMap { previous, current in
            let reset = current.0.startTime != previous.0.startTime
                || isLess(current.1, than: previous.1)
            let elapsed = elapsedSeconds(
                from: reset ? current.0.startTime : previous.0.endTime,
                to: current.0.endTime
            )
            guard elapsed > 0 else {
                return nil
            }
            let delta = reset ? current.1.doubleValue : difference(current.1, previous.1)
            return MetricChartSample(
                timestamp: current.0.endTime,
                value: delta / elapsed,
                isReset: reset
            )
        }
    }

    private static func deltaRates(
        _ points: [(MetricPointSnapshot, MetricNumber)]
    ) -> [MetricChartSample] {
        points.compactMap { point, value in
            let elapsed = elapsedSeconds(from: point.startTime, to: point.endTime)
            guard elapsed > 0 else {
                return nil
            }
            return MetricChartSample(timestamp: point.endTime, value: value.doubleValue / elapsed)
        }
    }

    private static func difference(_ current: MetricNumber, _ previous: MetricNumber) -> Double {
        switch (current, previous) {
        case let (.integer(current), .integer(previous)):
            let (difference, overflow) = current.subtractingReportingOverflow(previous)
            return overflow
                ? Double(current) - Double(previous)
                : Double(difference)
        default:
            return current.doubleValue - previous.doubleValue
        }
    }

    private static func isLess(_ current: MetricNumber, than previous: MetricNumber) -> Bool {
        switch (current, previous) {
        case let (.integer(current), .integer(previous)):
            current < previous
        default:
            current.doubleValue < previous.doubleValue
        }
    }

    private static func elapsedSeconds(
        from start: TelemetryTimestamp,
        to end: TelemetryTimestamp
    ) -> Double {
        guard end.nanosecondsSinceEpoch > start.nanosecondsSinceEpoch else {
            return 0
        }
        return Double(end.nanosecondsSinceEpoch - start.nanosecondsSinceEpoch) / 1_000_000_000
    }

    private static func formatBoundary(_ value: Double?) -> String {
        guard let value else {
            return "inf"
        }
        return value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}


#endif
