import HomelabCore
import SwiftUI

/// The home screen, and the one the app opens on. It was a list of three rows
/// and a sign-out button; it is now the `Status → Topic → Detail` grammar the
/// Grafana dashboards use — a hero that answers "is anything wrong", a strip of
/// numbers, then the workflows with their history under them, then what has
/// happened recently.
///
/// The sign-out button is gone from here entirely: a destructive control under
/// three buttons that deploy six hosts was one mis-tap from a surprise. It
/// lives behind the profile button in the corner, where every other app puts it.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    @State private var isShowingProfile = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                hero
                statusStrip

                section("Workflows") {
                    ForEach(state.snapshot.runRows) { row in
                        WorkflowCard(row: row, history: state.runHistory(for: row.workflow))
                    }
                }

                if !state.history.timeline.isEmpty {
                    section("Recent activity") {
                        ActivityTimeline(entries: Array(state.history.timeline.prefix(8)))
                    }
                }

                links
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Homelab")
        .navigationBarTitleDisplayMode(.large)
        .screenBackground()
        .refreshable {
            // Pull-to-refresh is the one gesture that means "I want the real
            // thing", so it always fetches the deep page rather than waiting
            // for the two-minute history window to come round.
            state.invalidateHistory()
            await state.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileButton(viewer: session.viewer) { isShowingProfile = true }
            }
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileView()
        }
    }

    // MARK: Status

    private var hero: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    StatusDot(
                        colour: palette.color(for: state.snapshot.glyph),
                        size: 9,
                        isPulsing: state.snapshot.hasActiveRun
                    )
                    Text(headline)
                        .font(Typeface.headline)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    if state.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(palette.textTertiary)
                    }
                }

                Text(subheadline)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)

                if let error = state.snapshot.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(Typeface.caption)
                            .lineLimit(3)
                    }
                    .foregroundStyle(palette.negative)
                }
            }
        }
    }

    private var headline: String {
        if let failing = state.snapshot.runRows.first(where: { $0.status == .failed }) {
            return "\(failing.workflow.displayName) failed"
        }
        if let active = state.snapshot.runRows.first(where: { $0.status.isActive }) {
            return "\(active.workflow.displayName) running"
        }
        if let waiting = state.snapshot.runRows.first(where: { $0.status == .awaitingApproval }) {
            return "\(waiting.workflow.displayName) awaiting approval"
        }
        return "All workflows green"
    }

    private var subheadline: String {
        var parts: [String] = []
        if let refreshed = state.snapshot.lastRefreshedAt {
            parts.append("Updated \(RelativeTime.ago(refreshed))")
        } else {
            parts.append("Not refreshed yet")
        }
        let deploys = state.history.deployCount(since: Date().addingTimeInterval(-7 * 86_400))
        if deploys > 0 {
            parts.append("\(deploys) deploy\(deploys == 1 ? "" : "s") this week")
        }
        return parts.joined(separator: " · ")
    }

    private var statusStrip: some View {
        StatStrip {
            StatTile(
                label: "Pass rate",
                value: state.history.successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                tint: passRateTint,
                detail: "last \(state.history.histories.flatMap(\.judged).count) runs"
            )
            StatTile(
                label: "Deploys",
                value: "\(state.history.deployCount(since: Date().addingTimeInterval(-7 * 86_400)))",
                detail: "7 days"
            )
            StatTile(
                label: "Open PRs",
                value: "\(state.snapshot.pullRequests.count)",
                tint: state.mergeablePullRequests.isEmpty ? nil : palette.accent,
                detail: state.mergeablePullRequests.isEmpty
                    ? "none ready"
                    : "\(state.mergeablePullRequests.count) ready"
            )
        }
    }

    private var passRateTint: Color? {
        guard let rate = state.history.successRate else { return nil }
        if rate >= 0.9 { return palette.positive }
        return rate >= 0.7 ? palette.warning : palette.negative
    }

    // MARK: Links

    private var links: some View {
        section("Links") {
            HStack(spacing: 8) {
                ForEach(state.quickLinks) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: link.symbolName)
                                .font(.system(size: 11, weight: .medium))
                            Text(link.title)
                                .font(Typeface.caption)
                        }
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.innerCorner, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: Metrics.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
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

/// One workflow: what it is doing now, what it has been doing, and the button
/// that starts or stops it.
private struct WorkflowCard: View {
    let row: RunRow
    let history: RunHistory?

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let history, !history.bars.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        RunDurationChart(bars: history.bars)
                        footer(history)
                    }
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { openURL(row.run?.url ?? state.repository.actionsURL) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            StatusDot(
                colour: palette.color(for: row.status),
                size: 8,
                isPulsing: row.status.isActive
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.workflow.displayName)
                    .font(Typeface.body)
                    .foregroundStyle(palette.textPrimary)
                Text(row.subtitle())
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            control
        }
    }

    private func footer(_ history: RunHistory) -> some View {
        HStack(spacing: 14) {
            if let rate = history.successRate {
                Text("\(Int((rate * 100).rounded()))% pass")
                    .font(Typeface.footnote)
                    .foregroundStyle(rate >= 0.9 ? palette.textSecondary : palette.warning)
            }
            if let median = history.medianDuration {
                Text("median \(RelativeTime.duration(median))")
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            TrendBadge(change: history.durationTrend, risingIsBad: true, threshold: 0.25)
            Spacer(minLength: 0)
            Text("last \(history.bars.count)")
                .font(Typeface.footnote)
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var control: some View {
        if state.busyWorkflows.contains(row.workflow) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
                .tint(palette.textSecondary)
        } else if state.canCancel(row.workflow) {
            IconButton(symbol: "stop.fill", tint: palette.negative) {
                Task { await state.cancel(row.workflow) }
            }
        } else {
            IconButton(
                symbol: "play.fill",
                tint: palette.accent,
                isEnabled: state.canTrigger(row.workflow)
            ) {
                Task { await state.trigger(row.workflow) }
            }
        }
    }
}

/// The last few runs across every workflow, newest first. The app's answer to
/// "what has this thing been doing" without opening github.com.
private struct ActivityTimeline: View {
    let entries: [ActivityHistory.TimelineEntry]

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                // Indices rather than `enumerated()`: a key path into a tuple
                // is not a thing Swift has, and the divider needs the position.
                ForEach(entries.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.border)
                            .frame(height: Metrics.hairline)
                    }
                    row(entries[index])
                }
            }
        }
    }

    private func row(_ entry: ActivityHistory.TimelineEntry) -> some View {
        HStack(spacing: 10) {
            StatusDot(colour: palette.color(for: entry.run.status), size: 6)

            Text(entry.workflow.displayName)
                .font(Typeface.caption)
                .foregroundStyle(palette.textPrimary)

            Text(RunStatusPresentation(entry.run.status).label)
                .font(Typeface.footnote)
                .foregroundStyle(palette.textSecondary)

            Spacer(minLength: 8)

            if let duration = entry.run.duration(now: Date()), !entry.run.status.isOpen {
                Text(RelativeTime.duration(duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
            }

            if let started = entry.run.startedAt {
                Text(RelativeTime.ago(started))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .onTapGesture { openURL(entry.run.url) }
    }
}

/// The avatar in the corner. It is both the way to the account sheet and the
/// answer to "which account is this phone acting as", which the app previously
/// never said anywhere.
struct ProfileButton: View {
    let viewer: GitHubViewer?
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(palette.surfaceRaised)
                    .overlay(Circle().strokeBorder(palette.border, lineWidth: Metrics.hairline))

                if let url = viewer?.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initial
                    }
                    .clipShape(Circle())
                } else {
                    initial
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
    }

    private var initial: some View {
        Text(viewer?.initial ?? "?")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
    }
}
