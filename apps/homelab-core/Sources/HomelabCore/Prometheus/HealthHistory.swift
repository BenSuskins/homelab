import Foundation

/// The queries the health screen is built from, in one place.
///
/// They are written against the Host Label and never `instance`, and they never
/// use `up` for liveness — host metrics are Remote-Written by Alloy and produce
/// no `up` series at all (ADR-0001). Keeping them here rather than inline in
/// the monitor means the instant tiles and the charts are provably reading the
/// same thing.
public enum HealthQuery {
    public static func cpuBusyFraction(rate interval: String) -> String {
        "1 - avg by (host) (rate(node_cpu_seconds_total{mode=\"idle\"}[\(interval)]))"
    }

    public static let memoryUsedFraction =
        "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"

    public static let rootDiskUsedFraction = """
    1 - (node_filesystem_avail_bytes{mountpoint="/"} \
    / node_filesystem_size_bytes{mountpoint="/"})
    """

    public static let load1 = "node_load1"

    /// Gatus exports one series per endpoint; `CONTEXT.md` flags this metric as
    /// load-bearing for the `gatus-endpoint-down` alert, which is a good reason
    /// to read what the alerting reads.
    public static let serviceSuccess = "gatus_results_endpoint_success"

    /// How many endpoints were failing at each moment — the one line that says
    /// whether this is a blip or a bad afternoon.
    public static let servicesDown = "sum(1 - \(serviceSuccess))"

    /// Availability across every endpoint, as a fraction.
    public static let serviceAvailability = "avg(\(serviceSuccess))"

    public static func networkBytes(rate interval: String) -> String {
        "sum by (host) (rate(node_network_receive_bytes_total{device!~\"lo|veth.*|docker.*|br-.*\"}[\(interval)]))"
    }
}

/// Which line a chart is asking for. An enum rather than four properties so a
/// view can iterate the set and a chart row is one generic component instead of
/// four near-identical ones.
public enum MetricKind: String, CaseIterable, Sendable, Identifiable, Codable {
    case cpu
    case memory
    case disk
    case load

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .load: "Load"
        }
    }

    /// Whether the values are a 0–1 fraction, which decides both the y-axis and
    /// how the number is formatted.
    public var isFraction: Bool {
        switch self {
        case .cpu, .memory, .disk: true
        case .load: false
        }
    }

    /// The ladder from `docs/grafana-dashboard-style.md`: nothing is coloured
    /// until it deserves to be.
    public func severity(for value: Double) -> MetricSeverity {
        switch self {
        case .cpu:
            value >= 0.9 ? .critical : (value >= 0.75 ? .warning : .nominal)
        case .memory:
            value >= 0.9 ? .critical : (value >= 0.8 ? .warning : .nominal)
        case .disk:
            value >= 0.9 ? .critical : (value >= 0.8 ? .warning : .nominal)
        case .load:
            value >= 8 ? .critical : (value >= 4 ? .warning : .nominal)
        }
    }

    public func format(_ value: Double) -> String {
        isFraction
            ? "\(Int((value * 100).rounded()))%"
            : String(format: "%.2f", value)
    }
}

public enum MetricSeverity: String, Sendable, Equatable, Codable {
    case nominal
    case warning
    case critical
}

/// Every line the health screen draws, for one window. Produced whole by a
/// refresh so the screen never shows one metric from now and another from ten
/// minutes ago.
public struct HealthHistory: Sendable, Equatable {
    public var window: MetricWindow
    public var cpu: [MetricSeries]
    public var memory: [MetricSeries]
    public var disk: [MetricSeries]
    public var load: [MetricSeries]
    /// Endpoints failing, over time. One series, not one per host.
    public var servicesDown: [MetricPoint]
    public var lastRefreshedAt: Date?

    public init(
        window: MetricWindow = .sixHours,
        cpu: [MetricSeries] = [],
        memory: [MetricSeries] = [],
        disk: [MetricSeries] = [],
        load: [MetricSeries] = [],
        servicesDown: [MetricPoint] = [],
        lastRefreshedAt: Date? = nil
    ) {
        self.window = window
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.load = load
        self.servicesDown = servicesDown
        self.lastRefreshedAt = lastRefreshedAt
    }

    public var isEmpty: Bool {
        cpu.isEmpty && memory.isEmpty && disk.isEmpty && load.isEmpty
    }

    public func series(_ kind: MetricKind) -> [MetricSeries] {
        switch kind {
        case .cpu: cpu
        case .memory: memory
        case .disk: disk
        case .load: load
        }
    }

    public func series(_ kind: MetricKind, host: String) -> MetricSeries? {
        series(kind).first { $0.host == host }
    }

    /// Every host that reported anything, in the order the screen lists them.
    public var hosts: [String] {
        var seen: Set<String> = []
        for kind in MetricKind.allCases {
            for host in series(kind).compactMap(\.host) { seen.insert(host) }
        }
        return seen.sorted()
    }

    /// The worst reading of this kind across all hosts, for the status strip.
    public func peak(_ kind: MetricKind) -> (host: String, value: Double)? {
        series(kind)
            .compactMap { entry -> (host: String, value: Double)? in
                guard let host = entry.host, let value = entry.latest else { return nil }
                return (host: host, value: value)
            }
            .max { $0.value < $1.value }
    }

    /// Host rows built from the last point of each line, so the tiles and the
    /// charts come from one fetch and cannot contradict each other.
    public var currentHosts: [HostHealth] {
        func latest(_ kind: MetricKind) -> [String: Double] {
            var result: [String: Double] = [:]
            for entry in series(kind) {
                guard let host = entry.host, let value = entry.latest else { continue }
                result[host] = value
            }
            return result
        }

        let cpuNow = latest(.cpu)
        let memoryNow = latest(.memory)
        let diskNow = latest(.disk)
        let loadNow = latest(.load)

        return hosts.map { host in
            HostHealth(
                host: host,
                load1: loadNow[host],
                memoryUsedFraction: memoryNow[host],
                rootDiskUsedFraction: diskNow[host],
                cpuUsedFraction: cpuNow[host]
            )
        }
    }
}
