import HomelabCore
import SwiftUI

struct LogsView: View {
    @Environment(Session.self) private var session

    private var monitor: LogMonitor { session.logMonitor }

    var body: some View {
        List {
            if monitor.isOffTailnet && monitor.snapshot.entries.isEmpty {
                ContentUnavailableView(
                    "Not connected to the tailnet",
                    systemImage: "network.slash",
                    description: Text(
                        "Loki is reachable over Tailscale only. "
                            + "Runs, pull requests, and health still work."
                    )
                )
            } else {
                controls
                logSection
            }
        }
        .navigationTitle("Logs")
        .refreshable { await monitor.refresh() }
        .task { await monitor.refresh() }
        .onDisappear { monitor.stopTail() }
        .onChange(of: monitor.selectedHost) { _, _ in refreshForFilterChange() }
        .onChange(of: monitor.selectedContainer) { _, _ in refreshForFilterChange() }
        .onChange(of: monitor.range) { _, _ in refreshForFilterChange() }
    }

    private var controls: some View {
        Section {
            Picker("Host", selection: hostSelection) {
                Text("All hosts").tag("")
                ForEach(monitor.snapshot.hosts, id: \.self) { host in
                    Text(host).tag(host)
                }
            }

            Picker("Container", selection: containerSelection) {
                Text("All containers").tag("")
                ForEach(monitor.snapshot.containers, id: \.self) { container in
                    Text(container).tag(container)
                }
            }

            Picker("Range", selection: rangeSelection) {
                Text("15 minutes").tag(TimeInterval(900))
                Text("1 hour").tag(TimeInterval(3600))
                Text("6 hours").tag(TimeInterval(21600))
                Text("24 hours").tag(TimeInterval(86400))
            }

            Toggle("Live tail", isOn: liveTail)
                .tint(.blue)

            if case .unreachable = monitor.failure {
                Label("Not connected to the tailnet", systemImage: "network.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if monitor.isTailing {
                Label("Listening for new entries", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var logSection: some View {
        Section {
            if monitor.snapshot.entries.isEmpty {
                ContentUnavailableView("No logs", systemImage: "doc.text.magnifyingglass")
            } else {
                ForEach(monitor.snapshot.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.timestamp, style: .time)
                                .foregroundStyle(.secondary)
                            if let host = entry.host {
                                Text(host)
                            }
                            if let container = entry.container {
                                Text(container)
                            }
                        }
                        .font(.caption2)

                        Text(entry.line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("Entries")
        }
    }

    private var hostSelection: Binding<String> {
        Binding(
            get: { monitor.selectedHost ?? "" },
            set: { monitor.selectedHost = $0.isEmpty ? nil : $0 }
        )
    }

    private var containerSelection: Binding<String> {
        Binding(
            get: { monitor.selectedContainer ?? "" },
            set: { monitor.selectedContainer = $0.isEmpty ? nil : $0 }
        )
    }

    private var rangeSelection: Binding<TimeInterval> {
        Binding(
            get: { monitor.range },
            set: { monitor.range = $0 }
        )
    }

    private var liveTail: Binding<Bool> {
        Binding(
            get: { monitor.isTailing },
            set: { monitor.setTailing($0) }
        )
    }

    private func refreshForFilterChange() {
        monitor.stopTail()
        Task { await monitor.refresh() }
    }
}
