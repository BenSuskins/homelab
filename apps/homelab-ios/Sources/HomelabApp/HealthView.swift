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
                windowPicker
                if let failure = monitor.failure {
                    RequestFailure(message: failure.displayMessage) { await monitor.refresh() }
                    if !monitor.snapshot.isEmpty {
                        OffTailnetNotice(detail: "Showing the last successful reading")
                    }
                }
                if monitor.snapshot.isEmpty {
                    if monitor.isRefreshing { ProgressView("Loading health…") }
                    else if monitor.failure == nil {
                        EmptyState(title: "No health data", message: "Prometheus reports no hosts or services.")
                    }
                } else {
                    statusStrip
                    if !monitor.history.servicesDown.isEmpty {
                        section("Availability") { availability }
                    }
                    section("Hosts") { hosts }
                    if !monitor.snapshot.services.isEmpty { section("Services") { services } }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
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
        ViewThatFits(in: .horizontal) {
            HStack { rangePicker; readAge }
            VStack(alignment: .leading) { rangePicker; readAge }
        }
    }

    private var rangePicker: some View {
        SegmentedControl(
                values: MetricWindow.allCases,
                title: { $0.label },
                selection: monitor.window,
                onSelect: { window in Task { await monitor.select(window) } }
        )
    }

    @ViewBuilder
    private var readAge: some View {
        if monitor.isRefreshing {
                ProgressView().controlSize(.mini).tint(palette.textTertiary)
            } else if let refreshed = monitor.snapshot.lastRefreshedAt {
                Text(RelativeTime.ago(refreshed))
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
        }
    }

    private var statusStrip: some View {
        StatStrip {
            StatTile(
                label: "Up",
                value: "\(monitor.snapshot.upCount)/\(monitor.snapshot.services.count)",
                tint: monitor.snapshot.services.isEmpty ? nil : (monitor.snapshot.downCount == 0 ? palette.positive : palette.negative),
                detail: monitor.snapshot.availability.map {
                    "\(Int(($0 * 100).rounded()))% available"
                } ?? "no endpoints"
            )
            StatTile(
                label: "Hosts",
                value: "\(monitor.snapshot.hosts.count)",
                tint: monitor.snapshot.strainedHosts.isEmpty ? nil : palette.warning,
                detail: "\(monitor.snapshot.hosts.filter(\.isReporting).count) reporting · \(monitor.snapshot.strainedHosts.count) strained"
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
                        expandedHost = expandedHost == host.host ? nil : host.host
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
            DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { _ in onToggle() })) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(MetricKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(kind.title).font(Typeface.caption)
                                Spacer()
                                if let series = history.series(kind, host: host.host), let peak = series.peak {
                                    Text("Peak \(kind.format(peak))").font(Typeface.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            if let series = history.series(kind, host: host.host), series.points.count > 1 {
                                MetricChart(series: series, kind: kind)
                                    .accessibilityLabel("\(host.host), \(kind.title)")
                            } else {
                                Text("No history for this range").font(Typeface.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }.padding(.top, 16)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if !isExpanded, let leading = leadingMetric,
                       let series = history.series(leading, host: host.host) {
                        Text("\(leading.title) history").font(Typeface.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Sparkline(points: series.points, tint: palette.color(for: host.severity))
                            .accessibilityLabel("\(host.host), \(leading.title) history")
                    }
                }
                .frame(minHeight: 44)
            }
        }
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


            }

            // Four readings on their own row: on a 375pt phone they do not fit
            // beside the host name without one of them truncating to nothing.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 12) {
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

    private var leadingMetric: MetricKind? {
        MetricKind.allCases.filter(\.isFraction)
            .filter { history.series($0, host: host.host)?.latest != nil }
            .max { (history.series($0, host: host.host)?.latest ?? 0) < (history.series($1, host: host.host)?.latest ?? 0) }
    }
}

/// The services on one host, as a dense grid of dots. Twenty-five services in
/// a list is four screens; as a grid it is one glance.
private struct ServiceGroupCard: View {
    let host: String
    let services: [ServiceHealth]

    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 6)]

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
                            Spacer(minLength: 0)
                            Text(service.isUp ? "Up" : "Down")
                                .font(Typeface.footnote)
                                .foregroundStyle(palette.color(isUp: service.isUp))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
