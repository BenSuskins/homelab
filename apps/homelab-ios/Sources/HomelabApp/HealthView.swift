import HomelabCore
import SwiftUI

/// Laid out on the grammar in `docs/grafana-dashboard-style.md` — a status
/// strip first, answering "is this thing OK right now" without interpretation,
/// then the detail — so the phone reads like the dashboards.
struct HealthView: View {
    @Environment(Session.self) private var session

    private var monitor: HealthMonitor { session.healthMonitor }

    var body: some View {
        List {
            if monitor.isOffTailnet && monitor.snapshot.isEmpty {
                ContentUnavailableView(
                    "Not connected to the tailnet",
                    systemImage: "network.slash",
                    description: Text(
                        "Prometheus is reachable over Tailscale only. "
                            + "Runs and pull requests still work."
                    )
                )
            } else {
                statusStrip
                hostSection
                serviceSection
            }
        }
        .navigationTitle("Health")
        .refreshable { await monitor.refresh() }
        .task { await monitor.refresh() }
    }

    private var statusStrip: some View {
        Section {
            HStack {
                Tile(
                    title: "Services",
                    value: "\(monitor.snapshot.services.count)",
                    tint: .secondary
                )
                Tile(
                    title: "Down",
                    value: "\(monitor.snapshot.downCount)",
                    tint: monitor.snapshot.downCount == 0 ? .green : .red
                )
                Tile(
                    title: "Hosts",
                    value: "\(monitor.snapshot.hosts.count)",
                    tint: .secondary
                )
            }
            .frame(maxWidth: .infinity)

            if monitor.isOffTailnet {
                Label(
                    "Showing the last reading — not on the tailnet",
                    systemImage: "network.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var hostSection: some View {
        Section("Hosts") {
            ForEach(monitor.snapshot.hosts) { host in
                VStack(alignment: .leading, spacing: 6) {
                    Text(host.host)
                        .font(.callout.weight(.medium))
                    HStack(spacing: 16) {
                        Reading(label: "load", value: host.load1.map { String(format: "%.2f", $0) })
                        Reading(label: "mem", value: host.memoryUsedFraction.map(Self.percent))
                        Reading(label: "disk", value: host.rootDiskUsedFraction.map(Self.percent))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var serviceSection: some View {
        ForEach(monitor.snapshot.servicesByHost, id: \.host) { group in
            Section(group.host) {
                ForEach(group.services) { service in
                    HStack {
                        Circle()
                            .fill(service.isUp ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(service.name)
                            .font(.callout)
                        Spacer()
                        Text(service.isUp ? "up" : "down")
                            .font(.caption)
                            .foregroundStyle(service.isUp ? .secondary : .red)
                    }
                }
            }
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Reading: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            // A metric that is not reporting says so, rather than showing a
            // zero that reads like a healthy measurement.
            Text(value ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(value == nil ? .tertiary : .secondary)
        }
    }
}
