import HomelabCore
import SwiftUI

/// Container logs from Loki, filtered by host and container rather than by a
/// free-text LogQL box — the label values come from Loki itself, so the pickers
/// can only produce a selector that matches something.
///
/// The filters were four rows of a settings-style form. They are now a row of
/// menus that reads like a query, which is what it is.
struct LogsView: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    @State private var isShowingProfile = false

    private var monitor: LogMonitor { session.logMonitor }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                if monitor.isOffTailnet && monitor.snapshot.entries.isEmpty {
                    EmptyState(
                        title: "Not connected to the tailnet",
                        message: "Loki is reachable over Tailscale only. "
                            + "Runs, pull requests and health still work.",
                        symbol: "network.slash"
                    )
                } else {
                    filters
                    summary
                    entries
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.large)
        .screenBackground()
        .refreshable { await monitor.refresh() }
        .task { await monitor.refresh() }
        .onDisappear { monitor.stopTail() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileButton(viewer: session.viewer) { isShowingProfile = true }
            }
        }
        .sheet(isPresented: $isShowingProfile) { ProfileView() }
    }

    // MARK: Controls

    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                FilterMenu(
                    label: "Host",
                    selection: monitor.selectedHost,
                    options: monitor.snapshot.hosts,
                    emptyTitle: "All hosts"
                ) { host in
                    monitor.selectedHost = host
                    reload()
                }

                FilterMenu(
                    label: "Container",
                    selection: monitor.selectedContainer,
                    options: monitor.snapshot.containers,
                    emptyTitle: "All containers"
                ) { container in
                    monitor.selectedContainer = container
                    reload()
                }
            }

            HStack(spacing: 8) {
                SegmentedControl(
                    values: LogRange.allCases,
                    title: { $0.label },
                    selection: LogRange.matching(monitor.range),
                    onSelect: { range in
                        monitor.range = range.seconds
                        reload()
                    }
                )

                Spacer(minLength: 4)

                tailToggle
            }
        }
    }

    private var tailToggle: some View {
        Button {
            monitor.setTailing(!monitor.isTailing)
        } label: {
            HStack(spacing: 5) {
                StatusDot(
                    colour: monitor.isTailing ? palette.positive : palette.textTertiary,
                    size: 6,
                    isPulsing: monitor.isTailing
                )
                Text("Live")
                    .font(Typeface.footnote)
                    .foregroundStyle(
                        monitor.isTailing ? palette.textPrimary : palette.textSecondary
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(monitor.isTailing ? palette.surface : palette.surfaceRaised)
            )
            .overlay(
                Capsule().strokeBorder(
                    monitor.isTailing ? palette.positive.opacity(0.4) : palette.border,
                    lineWidth: Metrics.hairline
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Text(monitor.query)
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if monitor.isRefreshing {
                ProgressView().controlSize(.mini).tint(palette.textTertiary)
            } else {
                let notable = monitor.snapshot.entries.filter { $0.level.isNotable }.count
                if notable > 0 {
                    Pill(text: "\(notable) notable", tint: palette.warning)
                }
                Text("\(monitor.snapshot.entries.count) lines")
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Lines

    @ViewBuilder
    private var entries: some View {
        if monitor.isOffTailnet {
            OffTailnetNotice(detail: "Showing the last read — not on the tailnet")
        }

        if monitor.snapshot.entries.isEmpty {
            EmptyState(
                title: "No logs in this window",
                message: "Nothing matched the selected host, container and range.",
                symbol: "doc.text.magnifyingglass"
            )
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    // Newest first: a log you opened on a phone is a log you
                    // are reading because something just happened.
                    ForEach(monitor.snapshot.entries.reversed()) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
        }
    }

    private func reload() {
        monitor.stopTail()
        Task { await monitor.refresh() }
    }
}

private struct LogRow: View {
    let entry: LokiLogEntry

    @Environment(\.palette) private var palette

    private var tint: Color {
        switch entry.level {
        case .error: palette.negative
        case .warning: palette.warning
        case .info, .debug: palette.textTertiary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(entry.level.isNotable ? tint : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                    if let container = entry.container {
                        Text(container)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let host = entry.host {
                        Text(host)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                    }
                    if entry.level.isNotable {
                        Text(entry.level.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                }

                Text(entry.line)
                    .font(Typeface.mono)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 7)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.level == .error ? palette.negative.opacity(0.05) : Color.clear)
    }
}

/// A menu of label values, with "all" as the first entry. A menu rather than a
/// wheel picker: there can be twenty-five containers, and a wheel makes you
/// scroll through them one at a time.
private struct FilterMenu: View {
    @Environment(\.palette) private var palette

    let label: String
    let selection: String?
    let options: [String]
    let emptyTitle: String
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            Button(emptyTitle) { onSelect(nil) }
            if !options.isEmpty {
                Divider()
                ForEach(options, id: \.self) { option in
                    Button(option) { onSelect(option) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(selection ?? "All")
                    .font(Typeface.caption)
                    .foregroundStyle(selection == nil ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: Metrics.hairline)
            )
        }
    }
}

/// The four windows the log view offers, as a type rather than four tagged
/// `TimeInterval` literals in a picker.
enum LogRange: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case hour
    case sixHours
    case day

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: 900
        case .hour: 3_600
        case .sixHours: 21_600
        case .day: 86_400
        }
    }

    var label: String {
        switch self {
        case .fifteenMinutes: "15M"
        case .hour: "1H"
        case .sixHours: "6H"
        case .day: "24H"
        }
    }

    /// The monitor stores a `TimeInterval`, so a stored value that is not one
    /// of these falls back to the nearest offered window rather than leaving
    /// the control with nothing selected.
    static func matching(_ interval: TimeInterval) -> LogRange {
        allCases.min { abs($0.seconds - interval) < abs($1.seconds - interval) } ?? .hour
    }
}
