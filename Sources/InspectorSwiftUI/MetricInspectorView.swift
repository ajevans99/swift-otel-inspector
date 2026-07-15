import Charts
import InspectorCore
import SwiftUI

public struct MetricInspectorView: View {
    @StateObject private var model: MetricInspectorModel
    @State private var selectedMetricID: MetricID?

    public init(store: MetricStore) {
        _model = StateObject(wrappedValue: MetricInspectorModel(store: store))
    }

    public var body: some View {
        NavigationSplitView {
            Group {
                if model.filteredMetrics.isEmpty {
                    MetricPlaceholder(
                        title: "No Metrics",
                        systemImage: "chart.xyaxis.line",
                        message: "Matching metric points will appear here."
                    )
                } else {
                    List(model.filteredMetrics, selection: $selectedMetricID) { metric in
                        MetricRow(metric: metric)
                            .tag(metric.id)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Metrics")
            .searchable(text: $model.searchText, prompt: "Name, service, scope, or attribute")
            .toolbar {
                Menu {
                    Picker("Type", selection: $model.kindFilter) {
                        ForEach(MetricKindFilter.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Service", selection: $model.selectedService) {
                        Text("All services").tag(String?.none)
                        ForEach(model.availableServices, id: \.self) {
                            Text($0).tag(Optional($0))
                        }
                    }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        } detail: {
            if let selectedMetric {
                MetricDetailView(metric: selectedMetric)
                    .id(selectedMetric.id)
            } else {
                MetricPlaceholder(
                    title: "Select a Metric",
                    systemImage: "chart.line.uptrend.xyaxis",
                    message: "Choose a metric to inspect its series and history."
                )
            }
        }
    }

    private var selectedMetric: MetricSnapshot? {
        model.filteredMetrics.first { $0.id == selectedMetricID }
    }
}

private struct MetricRow: View {
    let metric: MetricSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: MetricStyle.symbol(for: metric.kind))
                .font(.title3)
                .foregroundStyle(MetricStyle.color(for: metric.kind))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(MetricStyle.kindName(metric.kind))
                    Text(metric.resource.serviceName ?? "unknown service")
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(latestValue)
                    .font(.callout.monospacedDigit().weight(.semibold))
                Text("\(metric.series.count) series")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private var latestValue: String {
        guard let point = metric.series.compactMap(\.points.last).max(
            by: { $0.endTime < $1.endTime }
        ) else {
            return "No data"
        }
        return MetricStyle.value(point.value, unit: metric.unit)
    }
}

private struct MetricDetailView: View {
    let metric: MetricSnapshot
    @State private var selectedSeriesID: MetricSeriesID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCards
                seriesPicker
                chart
                    .frame(minHeight: 260)
                metadata
            }
            .padding()
        }
        .navigationTitle(metric.name)
        .onAppear {
            selectedSeriesID = selectedSeriesID ?? metric.series.first?.id
        }
    }

    private var selectedSeries: MetricSeriesSnapshot? {
        metric.series.first { $0.id == selectedSeriesID } ?? metric.series.first
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    MetricStyle.kindName(metric.kind),
                    systemImage: MetricStyle.symbol(for: metric.kind)
                )
                .foregroundStyle(MetricStyle.color(for: metric.kind))
                Spacer()
                Text(metric.resource.serviceName ?? "unknown service")
                    .foregroundStyle(.secondary)
            }
            if !metric.description.isEmpty {
                Text(metric.description)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
            MetricSummaryCard(title: "Latest", value: latestValue)
            MetricSummaryCard(title: "Series", value: "\(metric.series.count)")
            MetricSummaryCard(title: "Points", value: "\(metric.series.reduce(0) { $0 + $1.points.count })")
            MetricSummaryCard(
                title: "Temporality",
                value: metric.temporality.rawValue.capitalized
            )
        }
    }

    @ViewBuilder
    private var seriesPicker: some View {
        if metric.series.count > 1 {
            Picker("Series", selection: seriesSelection) {
                ForEach(metric.series) { series in
                    Text(MetricPresentation.seriesLabel(series))
                        .tag(Optional(series.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var seriesSelection: Binding<MetricSeriesID?> {
        Binding(
            get: {
                metric.series.contains { $0.id == selectedSeriesID }
                    ? selectedSeriesID
                    : metric.series.first?.id
            },
            set: { selectedSeriesID = $0 }
        )
    }

    @ViewBuilder
    private var chart: some View {
        if let series = selectedSeries, let point = series.points.last {
            switch point.value {
            case .number:
                numberChart(series)
            case let .histogram(histogram):
                explicitHistogramChart(histogram)
            case let .exponentialHistogram(histogram):
                exponentialHistogramChart(histogram)
            case let .summary(summary):
                summaryChart(summary)
            }
        } else {
            MetricPlaceholder(
                title: "No Points",
                systemImage: "chart.xyaxis.line",
                message: "This series has no retained metric points."
            )
        }
    }

    private func numberChart(_ series: MetricSeriesSnapshot) -> some View {
        let samples = MetricPresentation.chartSamples(metric: metric, series: series)
        return Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.timestamp.date),
                y: .value(axisTitle, sample.value)
            )
            .foregroundStyle(MetricStyle.color(for: metric.kind))
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Time", sample.timestamp.date),
                y: .value(axisTitle, sample.value)
            )
            .foregroundStyle(sample.isReset ? .orange : MetricStyle.color(for: metric.kind))
            .symbolSize(sample.isReset ? 70 : 35)
        }
        .chartYAxisLabel(axisTitle)
        .accessibilityLabel("\(metric.name) history")
    }

    private func explicitHistogramChart(
        _ histogram: MetricHistogramSnapshot
    ) -> some View {
        let buckets = MetricPresentation.explicitHistogramBuckets(histogram)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Bucket", bucket.label),
                y: .value("Count", bucket.count)
            )
            .foregroundStyle(MetricStyle.color(for: metric.kind).gradient)
        }
        .chartYAxisLabel("Count")
        .accessibilityLabel("\(metric.name) histogram buckets")
    }

    private func exponentialHistogramChart(
        _ histogram: MetricExponentialHistogramSnapshot
    ) -> some View {
        let buckets = MetricPresentation.exponentialHistogramBuckets(histogram)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Bucket index", bucket.label),
                y: .value("Count", bucket.count)
            )
            .foregroundStyle(MetricStyle.color(for: metric.kind).gradient)
        }
        .chartYAxisLabel("Count")
        .accessibilityLabel("\(metric.name) exponential histogram buckets")
    }

    private func summaryChart(_ summary: MetricSummarySnapshot) -> some View {
        Chart(summary.quantiles, id: \.quantile) { quantile in
            BarMark(
                x: .value("Quantile", quantile.quantile.formatted(.percent)),
                y: .value("Reported value", quantile.value)
            )
            .foregroundStyle(MetricStyle.color(for: metric.kind).gradient)
        }
        .chartYAxisLabel(metric.unit)
        .accessibilityLabel("\(metric.name) reported quantiles")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.headline)
            MetricMetadataRow(label: "Name", value: metric.name)
            MetricMetadataRow(label: "Unit", value: metric.unit.isEmpty ? "None" : metric.unit)
            MetricMetadataRow(label: "Scope", value: metric.instrumentationScope.name)
            if let series = selectedSeries {
                ForEach(series.attributes.sorted(by: { $0.key < $1.key }), id: \.key) {
                    MetricMetadataRow(label: $0.key, value: $0.value.displayValue)
                }
            }
        }
    }

    private var latestValue: String {
        guard let value = selectedSeries?.points.last?.value else {
            return "No data"
        }
        return MetricStyle.value(value, unit: metric.unit)
    }

    private var axisTitle: String {
        if case .sum(monotonic: true) = metric.kind {
            return metric.unit.isEmpty ? "Rate / second" : "\(metric.unit) / second"
        }
        return metric.unit
    }
}

private struct MetricSummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetricMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct MetricPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum MetricStyle {
    static func color(for kind: MetricKind) -> Color {
        switch kind {
        case .gauge: .blue
        case let .sum(monotonic): monotonic ? .green : .indigo
        case .histogram, .exponentialHistogram: .orange
        case .summary: .purple
        }
    }

    static func symbol(for kind: MetricKind) -> String {
        switch kind {
        case .gauge: "gauge.with.dots.needle.50percent"
        case .sum: "sum"
        case .histogram, .exponentialHistogram: "chart.bar.xaxis"
        case .summary: "chart.line.text.clipboard"
        }
    }

    static func kindName(_ kind: MetricKind) -> String {
        switch kind {
        case .gauge: "Gauge"
        case let .sum(monotonic): monotonic ? "Counter" : "Sum"
        case .histogram: "Histogram"
        case .exponentialHistogram: "Exponential histogram"
        case .summary: "Summary"
        }
    }

    static func value(_ point: MetricPointValue, unit: String) -> String {
        let suffix = unit.isEmpty ? "" : " \(unit)"
        switch point {
        case let .number(number):
            return number.doubleValue.formatted(.number.precision(.fractionLength(0 ... 2))) + suffix
        case let .histogram(histogram):
            return "\(histogram.count) samples"
        case let .exponentialHistogram(histogram):
            return "\(histogram.count) samples"
        case let .summary(summary):
            return "\(summary.count) samples"
        }
    }
}
