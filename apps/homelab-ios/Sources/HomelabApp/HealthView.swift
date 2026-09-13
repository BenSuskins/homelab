import HomelabCore
import SwiftUI

/// Laid out on the grammar in `docs/grafana-dashboard-style.md` — a status
/// strip first, answering "is this thing OK right now" without interpretation,
/// then topic sections, then the detail — so the phone reads like the
/// dashboards it is a companion to.
///
/// What it stopped being is a snapshot. Every number on it is the last point of
/// a line that is drawn directly underneath, over a window you choose, which is
/// the difference between "memory is at 82%" and "memory has been climbing all
/// afternoon".
struct HealthView: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    @State private var isShowingProfile = false
    @State private var expandedHost: String?

    private var monitor: HealthMonitor { session.healthMonitor }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if monitor.isOffTailnet && monitor.snapshot.isEmpty {
                    EmptyState(
                        title: "Not connected to the tailnet",
                        message: "Prometheus is reachable over Tailscale only. "
                            + "Runs and pull requests still work.",
                        symbol: "network.slash"
                    )
                } else {
                    windowPicker
                    statusStrip

                    if monitor.isOffTailnet {
                        OffTailnetNotice(detail: "Showing the last reading — not on the tailnet")
                    }

                    if !monitor.history.servicesDown.isEmpty {
                        section("Availability") { availability }
                    }

                    section("Hosts") { hosts }

                    if !monitor.snapshot.services.isEmpty {
                        section("Services") { services }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
        .screenBackground()
        .refreshable { await monitor.refresh() }
        .task { await monitor.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileButton(viewer: session.viewer) { isShowingProfile = true }
            }
        }
        .sheet(isPresented: $isShowingProfile) { ProfileView() }
    }

    // MARK: Status

    private var windowPicker: some View {
        HStack {
            // The monitor fetches on selection rather than from a change
            // observer, so a fast double-tap cannot leave two fetches racing to
            // write the same history.
            SegmentedControl(
                values: MetricWindow.allCases,
                title: { $0.label },
                selection: monitor.window,
                onSelect: { window in Task { await monitor.select(window) } }
            )

            Spacer(minLength: 8)

            if monitor.isRefreshing {
                ProgressView().controlSize(.mini).tint(palette.textTertiary)
            } else if let refreshed = monitor.snapshot.lastRefreshedAt {
                Text(RelativeTime.ago(refreshed))
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var statusStrip: some View {
        StatStrip {
            StatTile(
                label: "Up",
                value: "\(monitor.snapshot.upCount)/\(monitor.snapshot.services.count)",
                tint: monitor.snapshot.downCount == 0 ? palette.positive : palette.negative,
                detail: monitor.snapshot.availability.map {
                    "\(Int(($0 * 100).rounded()))% available"
                } ?? "no endpoints"
            )
            StatTile(
                label: "Hosts",
                value: "\(monitor.snapshot.hosts.count)",
                tint: monitor.snapshot.strainedHosts.isEmpty ? nil : palette.warning,
                detail: monitor.snapshot.strainedHosts.isEmpty
                    ? "all nominal"
                    : "\(monitor.snapshot.strainedHosts.count) strained"
            )
            peakTile
        }
    }

    /// The single worst reading anywhere, which is the tile that decides
    /// whether you keep reading.
    private var peakTile: some View {
        let peak = MetricKind.allCases
            .filter(\.isFraction)
            .compactMap { kind -> (kind: MetricKind, host: String, value: Double)? in
                guard let found = monitor.history.peak(kind) else { return nil }
                return (kind: kind, host: found.host, value: found.value)
            }
            .max { $0.value < $1.value }

        return StatTile(
            label: peak.map { "peak \($0.kind.title)" } ?? "Peak",
            value: peak.map { $0.kind.format($0.value) } ?? "—",
            tint: peak.map { palette.color(for: $0.kind.severity(for: $0.value)) },
            detail: peak?.host ?? "no data"
        )
    }

    // MARK: Sections

    private var availability: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Endpoints failing")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(monitor.window.longLabel)
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
                ServicesDownChart(points: monitor.history.servicesDown)
            }
        }
    }

    private var hosts: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(monitor.snapshot.hosts) { host in
                HostCard(
                    host: host,
                    history: monitor.history,
                    isExpanded: expandedHost == host.host,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedHost = expandedHost == host.host ? nil : host.host
                        }
                    }
                )
            }
        }
    }

    private var services: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(monitor.snapshot.servicesByHost, id: \.host) { group in
                ServiceGroupCard(host: group.host, services: group.services)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SectionHeader(title)
            content()
        }
    }
}

/// One host: four readings, a sparkline of the worst of them, and the full set
/// of charts when you tap it. Collapsed by default because six hosts × four
/// charts is a screen nobody reads.
private struct HostCard: View {
    let host: HostHealth
    let history: HealthHistory
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header

                if isExpanded {
                    ForEach(MetricKind.allCases) { kind in
                        if let series = history.series(kind, host: host.host), series.points.count > 1 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(kind.title)
                                        .font(Typeface.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                    Spacer()
                                    if let peak = series.peak {
                                        Text("peak \(kind.format(peak))")
                                            .font(Typeface.footnote)
                                            .foregroundStyle(palette.textTertiary)
                                    }
                                }
                                MetricChart(series: series, kind: kind)
                            }
                        }
                    }
                } else if let series = leadingSeries {
                    Sparkline(
                        points: series.points,
                        tint: palette.color(for: host.severity)
                    )
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onToggle)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(colour: palette.color(for: host.severity), size: 7)

                Text(host.host)
                    .font(Typeface.body)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 8)

                if !host.isReporting {
                    Pill(text: "no data", tint: palette.textTertiary)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }

            // Four readings on their own row: on a 375pt phone they do not fit
            // beside the host name without one of them truncating to nothing.
            HStack(spacing: 0) {
                ForEach(MetricKind.allCases) { kind in
                    Reading(
                        label: kind.title,
                        value: host.reading(kind).map { kind.format($0) },
                        tint: host.reading(kind).map { palette.color(for: kind.severity(for: $0)) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The line worth showing when collapsed: whichever metric is closest to a
    /// threshold, rather than always CPU.
    private var leadingSeries: MetricSeries? {
        MetricKind.allCases
            .filter(\.isFraction)
            .compactMap { kind -> (series: MetricSeries, value: Double)? in
                guard let series = history.series(kind, host: host.host),
                      let latest = series.latest else { return nil }
                return (series: series, value: latest)
            }
            .max { $0.value < $1.value }?
            .series
    }
}

/// The services on one host, as a dense grid of dots. Twenty-five services in
/// a list is four screens; as a grid it is one glance.
private struct ServiceGroupCard: View {
    let host: String
    let services: [ServiceHealth]

    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 6)]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(host)
                        .font(Typeface.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    let down = services.filter { !$0.isUp }.count
                    Pill(
                        text: down == 0 ? "all up" : "\(down) down",
                        tint: down == 0 ? palette.positive : palette.negative
                    )
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(services) { service in
                        HStack(spacing: 6) {
                            StatusDot(colour: palette.color(isUp: service.isUp), size: 6)
                            Text(service.name)
                                .font(Typeface.caption)
                                .foregroundStyle(
                                    service.isUp ? palette.textSecondary : palette.textPrimary
                                )
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}
