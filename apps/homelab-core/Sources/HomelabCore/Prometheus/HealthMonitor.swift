import Foundation
import Observation

/// Owns the health screen's data. Separate from `AppState` on purpose: GitHub
/// works from anywhere and Prometheus only works on the tailnet, so the two are
/// independent failure domains. Folding them together would let an unreachable
/// Prometheus put an error banner over a perfectly healthy runs list.
@MainActor
@Observable
public final class HealthMonitor {
    public private(set) var snapshot: HealthSnapshot = HealthSnapshot()
    public private(set) var isRefreshing = false
    /// Non-nil means the health screen alone is degraded. Nothing else reads it.
    public private(set) var failure: PrometheusFailure?

    private let client: PrometheusClient

    public init(client: PrometheusClient = PrometheusClient()) {
        self.client = client
    }

    /// Whether to show "not connected to the tailnet" rather than an error:
    /// off-tailnet is the expected state of a phone, not a fault to report.
    public var isOffTailnet: Bool {
        if case .unreachable = failure { return true }
        return false
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let services = try await fetchServices()
            let hosts = try await fetchHosts()
            snapshot = HealthSnapshot(
                services: services,
                hosts: hosts,
                lastRefreshedAt: Date()
            )
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
        let samples = try await client.instantQuery("gatus_results_endpoint_success")

        return samples.compactMap { sample -> ServiceHealth? in
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

    /// Host metrics are Remote-Written by Alloy, so they produce no `up` series
    /// and `up` must not be used to enumerate hosts (ADR-0001). The metrics
    /// themselves are the enumeration.
    private func fetchHosts() async throws(PrometheusFailure) -> [HostHealth] {
        let load = try await client.instantQuery("node_load1")
        let memory = try await client.instantQuery(
            "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
        )
        let disk = try await client.instantQuery(
            """
            1 - (node_filesystem_avail_bytes{mountpoint="/"} \
            / node_filesystem_size_bytes{mountpoint="/"})
            """
        )

        return Self.combine(load: load, memory: memory, disk: disk)
    }

    /// `nonisolated` because it is a pure function of its arguments — the
    /// class is `@MainActor` for its observable state, not for this.
    nonisolated static func combine(
        load: [PrometheusSample],
        memory: [PrometheusSample],
        disk: [PrometheusSample]
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

        let hosts = Set(loads.keys).union(memories.keys).union(disks.keys)
        return hosts.sorted().map { host in
            HostHealth(
                host: host,
                load1: loads[host],
                memoryUsedFraction: memories[host],
                rootDiskUsedFraction: disks[host]
            )
        }
    }
}
