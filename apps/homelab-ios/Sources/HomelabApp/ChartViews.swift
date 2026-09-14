import Charts
import HomelabCore
import SwiftUI

// Every chart in the app. Swift Charts rather than a Grafana webview: Grafana
// is `secured: true`, so an embedded dashboard meets an Authelia login inside
// the webview, and its panels are laid out for a desktop anyway.
//
// They follow the same rules as the dashboards in `config/grafana/` — the axis
// starts at zero for a fraction, the threshold colours are the ladder from
// `MetricKind.severity(for:)`, and a gap in the data stays a gap.

/// The last several runs of one workflow as duration bars, coloured by outcome.
/// The shape of the deploy history in one glance: how long, how often, and
/// which ones went red.
struct RunDurationChart: View {
    @Environment(\.palette) private var palette

    let bars: [RunBar]
    var height: CGFloat = 46

    var body: some View {
        if bars.isEmpty {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surfaceRaised)
                .frame(height: height)
                .overlay(
                    Text("No completed runs yet")
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                )
        } else {
            Chart(bars) { bar in
                BarMark(
                    x: .value("Run", bar.index),
                    y: .value("Minutes", bar.duration / 60),
                    width: .fixed(5)
                )
                .foregroundStyle(palette.color(for: bar.status))
                .cornerRadius(1.5)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.background(palette.surfaceRaised.opacity(0.5))
            }
            .frame(height: height)
        }
    }
}

/// A host metric over the selected window: an area under a line, the fill
/// tinted by how bad the current reading is.
struct MetricChart: View {
    @Environment(\.palette) private var palette

    let series: MetricSeries
    let kind: MetricKind
    var height: CGFloat = 92

    private var tint: Color {
        guard let latest = series.latest else { return palette.textTertiary }
        return palette.color(for: kind.severity(for: latest))
    }

    /// A fraction is always drawn against 0–100%, so two hosts' charts are
    /// comparable by eye. Load has no ceiling, so it scales to what it did.
    private var domain: ClosedRange<Double> {
        if kind.isFraction { return 0...1 }
        let peak = series.peak ?? 1
        return 0...max(peak * 1.2, 1)
    }

    var body: some View {
        Chart {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value(kind.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(series.points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(kind.title, point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel()
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel {
                    if let reading = value.as(Double.self) {
                        Text(kind.format(reading))
                            .font(Typeface.footnote)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
    }
}

/// A line with no axes, sized to sit inside a row. Used where the shape matters
/// and the numbers are already written next to it.
struct Sparkline: View {
    @Environment(\.palette) private var palette

    let points: [MetricPoint]
    var tint: Color?
    var height: CGFloat = 26

    var body: some View {
        if points.count < 2 {
            Color.clear.frame(height: height)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.3))
                .foregroundStyle(tint ?? palette.accent)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
        }
    }
}

/// How many endpoints were failing, over the window. A step line rather than a
/// smoothed one: the count is an integer and the moment it changed is the
/// interesting part, so interpolating between 0 and 3 would invent readings.
struct ServicesDownChart: View {
    @Environment(\.palette) private var palette

    let points: [MetricPoint]
    var height: CGFloat = 60

    private var peak: Double { points.map(\.value).max() ?? 0 }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.date),
                y: .value("Down", point.value)
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(
                LinearGradient(
                    colors: [palette.negative.opacity(0.3), palette.negative.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.date),
                y: .value("Down", point.value)
            )
            .interpolationMethod(.stepEnd)
            .lineStyle(StrokeStyle(lineWidth: 1.4))
            .foregroundStyle(peak == 0 ? palette.positive : palette.negative)
        }
        .chartYScale(domain: 0...max(peak * 1.3, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel()
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel {
                    if let count = value.as(Double.self) {
                        Text("\(Int(count))")
                            .font(Typeface.footnote)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
    }
}
