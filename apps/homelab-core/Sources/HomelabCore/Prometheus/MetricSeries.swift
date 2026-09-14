import Foundation

/// One sample of a range query: a moment and a number. `Identifiable` by its
/// date because Swift Charts wants a stable identity per point and a timestamp
/// is unique within a series by construction.
public struct MetricPoint: Sendable, Equatable, Codable, Identifiable {
    public let date: Date
    public let value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A range query's result for one label set — the shape a chart draws.
///
/// The instant-query equivalent is `PrometheusSample`: same labels, one value
/// instead of a line. Both keep the raw label dictionary rather than a decoded
/// struct, because which labels matter differs per query and ADR-0001 has
/// already settled the only one that identifies a host.
public struct MetricSeries: Sendable, Equatable, Identifiable {
    public let labels: [String: String]
    /// Oldest first, as Prometheus returns them, which is also the order a
    /// chart wants to plot.
    public let points: [MetricPoint]

    public var id: String {
        labels.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    /// The Host Label, per ADR-0001. Never `instance`.
    public var host: String? { labels["host"] }

    public subscript(label: String) -> String? { labels[label] }

    public init(labels: [String: String], points: [MetricPoint]) {
        self.labels = labels
        self.points = points
    }

    /// The most recent reading — what a KPI tile shows, so the tile and the
    /// chart beside it are drawn from one fetch and cannot disagree.
    public var latest: Double? { points.last?.value }

    public var peak: Double? { points.map(\.value).max() }

    public var mean: Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }

    /// The y-axis range a chart should use, padded so a flat line does not sit
    /// on the axis and a noisy one is not clipped.
    public var bounds: ClosedRange<Double>? {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }
        if low == high { return (low - 0.5)...(high + 0.5) }
        let padding = (high - low) * 0.15
        return (low - padding)...(high + padding)
    }

    /// The change across the window, as a fraction of the first reading —
    /// the arrow beside a KPI. Nil when there is nothing to compare against.
    public var trend: Double? {
        guard let first = points.first?.value, let last = points.last?.value, first != 0 else {
            return nil
        }
        return (last - first) / abs(first)
    }
}

/// How far back a chart looks. Each case carries its own step, chosen to land
/// near 120 points: enough to show shape, few enough that Prometheus answers a
/// phone quickly and the line does not turn into noise.
public enum MetricWindow: String, CaseIterable, Sendable, Identifiable, Codable {
    case hour
    case sixHours
    case day
    case week

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .hour: 3_600
        case .sixHours: 21_600
        case .day: 86_400
        case .week: 604_800
        }
    }

    public var step: TimeInterval {
        switch self {
        case .hour: 30
        case .sixHours: 180
        case .day: 720
        case .week: 5_400
        }
    }

    /// Short enough for a segmented control on a phone.
    public var label: String {
        switch self {
        case .hour: "1H"
        case .sixHours: "6H"
        case .day: "24H"
        case .week: "7D"
        }
    }

    public var longLabel: String {
        switch self {
        case .hour: "Last hour"
        case .sixHours: "Last 6 hours"
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        }
    }

    /// The rate window for counter queries. It has to be several scrape
    /// intervals wide or `rate()` returns nothing, and it should widen with the
    /// step or a 7-day chart samples gaps between 30-second windows.
    public var rateInterval: String {
        switch self {
        case .hour: "2m"
        case .sixHours: "5m"
        case .day: "15m"
        case .week: "1h"
        }
    }
}
