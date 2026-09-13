import Foundation
import Observation

/// Owns the health screen's data. Separate from `AppState` on purpose: GitHub
/// works from anywhere and Prometheus only works on the tailnet, so the two are
/// independent failure domains. Folding them together would let an unreachable
/// Prometheus put an error banner over a perfectly healthy runs list.
///
/// Everything on the screen comes from range queries rather than instant ones,
/// with the tiles reading the last point of the same line the chart draws. That
/// is one fetch instead of two and it makes a tile disagreeing with the chart
/// beside it impossible rather than merely unlikely.
@MainActor
@Observable
public final class HealthMonitor {
    public private(set) var snapshot: HealthSnapshot = HealthSnapshot()
    public private(set) var history: HealthHistory = HealthHistory()
    public private(set) var isRefreshing = false
    /// Non-nil means the health screen alone is degraded. Nothing else reads it.
    public private(set) var failure: PrometheusFailure?

    /// How far back the charts look. Setting it does not fetch — the view calls
    /// `refresh()`, so a fast double-tap on the picker cannot leave two fetches
    /// racing to write the same history.
    public var window: MetricWindow = .sixHours

    private let client: PrometheusClient
    private let cache: HealthCache?

    public init(client: PrometheusClient = PrometheusClient(), cache: HealthCache? = nil) {
        self.client = client
        self.cache = cache
        if let cached = cache?.load() {
            snapshot = cached
        }
    }

    /// Whether to show "not connected to the tailnet" rather than an error:
    /// off-tailnet is the expected state of a phone, not a fault.
    public var isOffTailnet: Bool {
        if case .unreachable = failure { return true }
        return false
    }

    public func select(_ window: MetricWindow) async {
        guard window != self.window else { return }
        self.window = window
        await refresh()
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let window = self.window
        do {
            let services = try await fetchServices()
            let history = try await fetchHistory(window: window)

            self.history = history
            snapshot = HealthSnapshot(
                services: services,
                hosts: history.currentHosts,
                lastRefreshedAt: Date()
            )
            cache?.save(snapshot)
            failure = nil
        } catch {
            // Keep whatever was last seen on screen, as the runs list does.
            failure = error
        }
    }

    /// Gatus exports one series per endpoint; `CONTEXT.md` flags this metric as
    /// load-bearing for the `gatus-endpoint-down` alert rule, which is a good
    /// reason to read the same thing the alerting reads.
    private func fetchServices() async throws(PrometheusFailure) -> [ServiceHealth] {
        let samples = try await client.instantQuery(HealthQuery.serviceSuccess)
        return Self.services(from: samples)
    }

    /// Sequential rather than `async let`: six concurrent queries against a
    /// single-node Prometheus over a tailnet buys nothing worth the typed-throws
    /// contortions, and a partial failure here should abandon the whole refresh
    /// rather than leave half a screen.
    private func fetchHistory(
        window: MetricWindow
    ) async throws(PrometheusFailure) -> HealthHistory {
        let now = Date()
        let cpu = try await client.rangeQuery(
            HealthQuery.cpuBusyFraction(rate: window.rateInterval),
            window: window,
            now: now
        )
        let memory = try await client.rangeQuery(
            HealthQuery.memoryUsedFraction, window: window, now: now
        )
        let disk = try await client.rangeQuery(
            HealthQuery.rootDiskUsedFraction, window: window, now: now
        )
        let load = try await client.rangeQuery(
            HealthQuery.load1, window: window, now: now
        )
        let down = try await client.rangeQuery(
            HealthQuery.servicesDown, window: window, now: now
        )

        return HealthHistory(
            window: window,
            cpu: cpu,
            memory: memory,
            disk: disk,
            load: load,
            servicesDown: down.first?.points ?? [],
            lastRefreshedAt: now
        )
    }

    /// `nonisolated` because it is a pure function of its argument — the class
    /// is `@MainActor` for its observable state, not for this.
    nonisolated static func services(from samples: [PrometheusSample]) -> [ServiceHealth] {
        samples.compactMap { sample -> ServiceHealth? in
            guard let name = sample["name"] else { return nil }
            return ServiceHealth(
                name: name,
                // Gatus's `group` is the Service Entry's friendly_name, which
                // is the Host Label under another name.
                host: sample["group"] ?? "Unknown",
                isUp: sample.value == 1
            )
        }
        .sorted { ($0.host, $0.name) < ($1.host, $1.name) }
    }

    /// Host rows from three instant queries. Superseded on screen by
    /// `HealthHistory.currentHosts`, and kept because it is the pure statement
    /// of the rule ADR-0001 sets — a host is whatever carries a Host Label, a
    /// NaN is missing data rather than a reading of zero — and the tests that
    /// pin that rule down are cheaper to run against it than against a range
    /// query's wire format.
    nonisolated static func combine(
        load: [PrometheusSample],
        memory: [PrometheusSample],
        disk: [PrometheusSample],
        cpu: [PrometheusSample] = []
    ) -> [HostHealth] {
        func byHost(_ samples: [PrometheusSample]) -> [String: Double] {
            var result: [String: Double] = [:]
            for sample in samples {
                guard let host = sample["host"], !sample.value.isNaN else { continue }
                result[host] = sample.value
            }
            return result
        }

        let loads = byHost(load)
        let memories = byHost(memory)
        let disks = byHost(disk)
        let cpus = byHost(cpu)

        let hosts = Set(loads.keys)
            .union(memories.keys)
            .union(disks.keys)
            .union(cpus.keys)

        return hosts.sorted().map { host in
            HostHealth(
                host: host,
                load1: loads[host],
                memoryUsedFraction: memories[host],
                rootDiskUsedFraction: disks[host],
                cpuUsedFraction: cpus[host]
            )
        }
    }
}
