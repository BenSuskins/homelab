import HomelabCore
import SwiftUI

/// Container logs from Loki, filtered by host and container rather than by a
/// free-text LogQL box — the label values come from Loki itself, so the pickers
/// can only produce a selector that matches something.
///
/// The filters were four rows of a settings-style form. They are now a row of
/// menus that reads like a query, which is what it is.
///
/// Rows show a line taken apart rather than a line printed: `LogRecord` reads
/// the level, the timestamp and the message out of whichever shape the
/// container writes, and the rest of the fields become chips. Tapping a row
/// opens everything that was parsed out of it, plus the raw line underneath.
struct LogsView: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    @State private var isShowingProfile = false
    @State private var inspected: LokiLogEntry?

    private var monitor: LogMonitor { session.logMonitor }

    var body: some View {
        // A binding into the monitor, for the search field only.
        @Bindable var bindable = session.logMonitor

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
                    levels
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
        .searchable(
            text: $bindable.search,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Find in these lines"
        )
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
        .sheet(item: $inspected) { entry in
            LogDetailView(entry: entry) { container in
                inspected = nil
                monitor.selectedContainer = container
                reload()
            }
        }
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

    /// The level filter. Counts rather than bare names, because the useful
    /// question on this screen is "is there anything red in the last hour" and
    /// the chips answer it before you tap one.
    ///
    /// Filtered on the device: Alloy ships container stdout verbatim, so there
    /// is no level label for Loki to select on.
    private var levels: some View {
        let counts = monitor.levelCounts

        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                LevelChip(
                    title: "All",
                    count: counts.values.reduce(0, +),
                    tint: palette.textSecondary,
                    isSelected: monitor.selectedLevel == nil
                ) {
                    monitor.selectedLevel = nil
                }

                ForEach(LogLevel.bySeverity, id: \.self) { level in
                    LevelChip(
                        title: level.label,
                        count: counts[level] ?? 0,
                        tint: palette.color(for: level),
                        isSelected: monitor.selectedLevel == level
                    ) {
                        monitor.selectedLevel = monitor.selectedLevel == level ? nil : level
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
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
                let shown = monitor.visibleEntries.count
                let total = monitor.snapshot.entries.count
                Text(shown == total ? "\(total) lines" : "\(shown) of \(total)")
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

        let visible = monitor.visibleEntries

        if visible.isEmpty {
            EmptyState(
                title: monitor.snapshot.entries.isEmpty
                    ? "No logs in this window"
                    : "Nothing matches these filters",
                message: monitor.snapshot.entries.isEmpty
                    ? "Nothing matched the selected host, container and range."
                    : "\(monitor.snapshot.entries.count) lines were read — "
                        + "none of them match the level or the search.",
                symbol: "doc.text.magnifyingglass"
            )

            if monitor.hasFilters {
                Button("Clear filters") { monitor.clearFilters() }
                    .font(Typeface.caption)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Card(padding: 0) {
                // Lazy, because the window is five hundred lines and each row
                // is now a header, a message and a set of chips rather than
                // one `Text`.
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 {
                            Rectangle()
                                .fill(palette.border)
                                .frame(height: Metrics.hairline)
                        }
                        Button { inspected = item.element } label: {
                            LogRow(entry: item.element)
                        }
                        .buttonStyle(.plain)
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

// MARK: Row

/// One line. Three bands: metadata, the message, then the fields that did not
/// fit — which is the same `Status → Topic → Detail` grammar the dashboards
/// use, turned on its side.
private struct LogRow: View {
    let entry: LokiLogEntry

    @Environment(\.palette) private var palette

    /// Three is what fits on a phone without the row wrapping. The rest are one
    /// tap away, and the count says how many there are.
    private static let chipLimit = 3

    private var record: LogRecord { entry.record }
    private var tint: Color { palette.color(for: record.level) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(record.level.isNotable ? tint : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                header
                message
                if !record.fields.isEmpty { chips }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 9)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(record.level == .error ? palette.negative.opacity(0.05) : Color.clear)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(LogTime.clock(entry.writtenAt))
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

            Spacer(minLength: 0)

            if record.level.isNotable {
                Text(record.level.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
    }

    private var message: some View {
        Text(record.message)
            .font(record.isStructured ? Typeface.caption : Typeface.mono)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chips: some View {
        let shown = record.fields.prefix(Self.chipLimit)
        let hidden = record.fields.count - shown.count

        return HStack(spacing: 4) {
            ForEach(shown) { field in
                FieldChip(field: field)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A `key=value` pair, sized so three of them fit across a phone. The key is
/// dim and the value is not, because you scan the values.
struct FieldChip: View {
    let field: LogField

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            Text(field.key)
                .foregroundStyle(palette.textTertiary)
            Text(field.value)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(palette.surfaceRaised)
        )
        .frame(maxWidth: 130, alignment: .leading)
    }
}

/// One level and how many lines of it there are.
private struct LevelChip: View {
    let title: String
    let count: Int
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(isSelected ? tint.opacity(0.8) : palette.textTertiary)
            }
            .foregroundStyle(isSelected ? tint : palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.14) : palette.surfaceRaised)
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? tint.opacity(0.5) : Color.clear,
                    lineWidth: Metrics.hairline
                )
            )
        }
        .buttonStyle(.plain)
        // A level with nothing in it is still worth showing — it is the
        // evidence that there are no errors — but it should not invite a tap.
        .disabled(count == 0 && !isSelected)
        .opacity(count == 0 && !isSelected ? 0.45 : 1)
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

/// Log timestamps, to the millisecond. Two lines a millisecond apart is the
/// difference between a cause and a coincidence, so the row shows it.
///
/// `nonisolated(unsafe)` for the same reason as `Timestamps` in the core: a
/// formatter is expensive to build and is hit once per row, and one that is
/// never reconfigured after construction is safe to read from anywhere.
enum LogTime {
    nonisolated(unsafe) private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    nonisolated(unsafe) private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm:ss.SSS"
        return formatter
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }
}

