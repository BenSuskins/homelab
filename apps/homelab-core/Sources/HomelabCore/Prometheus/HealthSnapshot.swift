import Foundation

/// One monitored service, as Gatus sees it and Prometheus reports it.
public struct ServiceHealth: Sendable, Equatable, Identifiable, Codable {
    public let name: String
    /// The Host Label — the Friendly Name of the host, per ADR-0001. Never the
    /// `instance` label, which holds a raw IP and exists for Prometheus's own
    /// bookkeeping rather than for display.
    public let host: String
    public let isUp: Bool

    public var id: String { "\(host)/\(name)" }

    public init(name: String, host: String, isUp: Bool) {
        self.name = name
        self.host = host
        self.isUp = isUp
    }
}

/// One host, with the handful of numbers worth reading on a phone.
public struct HostHealth: Sendable, Equatable, Identifiable, Codable {
    public let host: String
    public let load1: Double?
    public let memoryUsedFraction: Double?
    public let rootDiskUsedFraction: Double?
    public let cpuUsedFraction: Double?

    public var id: String { host }

    public init(
        host: String,
        load1: Double? = nil,
        memoryUsedFraction: Double? = nil,
        rootDiskUsedFraction: Double? = nil,
        cpuUsedFraction: Double? = nil
    ) {
        self.host = host
        self.load1 = load1
        self.memoryUsedFraction = memoryUsedFraction
        self.rootDiskUsedFraction = rootDiskUsedFraction
        self.cpuUsedFraction = cpuUsedFraction
    }

    public func reading(_ kind: MetricKind) -> Double? {
        switch kind {
        case .cpu: cpuUsedFraction
        case .memory: memoryUsedFraction
        case .disk: rootDiskUsedFraction
        case .load: load1
        }
    }

    /// The worst thing this host is doing, which is what a single-row summary
    /// should colour itself by.
    public var severity: MetricSeverity {
        let levels = MetricKind.allCases.compactMap { kind in
            reading(kind).map { kind.severity(for: $0) }
        }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warning) { return .warning }
        return .nominal
    }

    /// True when nothing reported at all — a host in the list because another
    /// query saw it, with no numbers of its own.
    public var isReporting: Bool {
        MetricKind.allCases.contains { reading($0) != nil }
    }
}

/// Everything the health screen renders, in the same shape as `StatusSnapshot`:
/// an immutable value produced by a pure function, so the view holds no logic.
public struct HealthSnapshot: Sendable, Equatable, Codable {
    public var services: [ServiceHealth]
    public var hosts: [HostHealth]
    public var lastRefreshedAt: Date?

    public init(
        services: [ServiceHealth] = [],
        hosts: [HostHealth] = [],
        lastRefreshedAt: Date? = nil
    ) {
        self.services = services
        self.hosts = hosts
        self.lastRefreshedAt = lastRefreshedAt
    }

    public var downCount: Int { services.filter { !$0.isUp }.count }
    public var upCount: Int { services.filter(\.isUp).count }
    public var isEmpty: Bool { services.isEmpty && hosts.isEmpty }

    /// The share of endpoints currently passing, as a fraction. Nil rather than
    /// 1.0 when nothing is being monitored, so an empty read cannot render as
    /// a perfect score.
    public var availability: Double? {
        guard !services.isEmpty else { return nil }
        return Double(upCount) / Double(services.count)
    }

    /// The services that are down, worst-first ordering for a status strip.
    public var downServices: [ServiceHealth] {
        services.filter { !$0.isUp }.sorted { ($0.host, $0.name) < ($1.host, $1.name) }
    }

    /// Hosts whose numbers have crossed a threshold, for the same strip.
    public var strainedHosts: [HostHealth] {
        hosts.filter { $0.severity != .nominal }
    }

    /// Grouped by Host Label for display, which is the axis the Grafana
    /// dashboards use and the one Homepage groups by.
    public var servicesByHost: [(host: String, services: [ServiceHealth])] {
        Dictionary(grouping: services, by: \.host)
            .map { (host: $0.key, services: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.host < $1.host }
    }
}
