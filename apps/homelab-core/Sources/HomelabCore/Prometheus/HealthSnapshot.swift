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

    public var id: String { host }

    public init(
        host: String,
        load1: Double? = nil,
        memoryUsedFraction: Double? = nil,
        rootDiskUsedFraction: Double? = nil
    ) {
        self.host = host
        self.load1 = load1
        self.memoryUsedFraction = memoryUsedFraction
        self.rootDiskUsedFraction = rootDiskUsedFraction
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
    public var isEmpty: Bool { services.isEmpty && hosts.isEmpty }

    /// Grouped by Host Label for display, which is the axis the Grafana
    /// dashboards use and the one Homepage groups by.
    public var servicesByHost: [(host: String, services: [ServiceHealth])] {
        Dictionary(grouping: services, by: \.host)
            .map { (host: $0.key, services: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.host < $1.host }
    }
}
