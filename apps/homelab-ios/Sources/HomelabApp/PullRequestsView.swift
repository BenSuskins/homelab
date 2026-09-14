import HomelabCore
import SwiftUI

/// Open pull requests, with the one that can be merged made obvious and the
/// consequence of merging said out loud: a squash onto `main` starts Update
/// Homelab, which deploys six hosts.
struct PullRequestsView: View {
    @Environment(AppState.self) private var state
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    @State private var isShowingProfile = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if state.snapshot.pullRequests.isEmpty {
                    EmptyState(
                        title: "No open pull requests",
                        message: "Renovate will be along shortly.",
                        symbol: "checkmark.circle",
                        tint: palette.positive
                    )
                } else {
                    strip

                    if !state.mergeablePullRequests.isEmpty {
                        group("Ready to merge", state.mergeablePullRequests)
                    }
                    if !blocked.isEmpty {
                        group("Waiting", blocked)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Pull requests")
        .navigationBarTitleDisplayMode(.large)
        .screenBackground()
        .refreshable { await state.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileButton(viewer: session.viewer) { isShowingProfile = true }
            }
        }
        .sheet(isPresented: $isShowingProfile) { ProfileView() }
    }

    private var blocked: [PullRequestSummary] {
        state.snapshot.pullRequests.filter { !$0.canMerge }
    }

    private var strip: some View {
        StatStrip {
            StatTile(label: "Open", value: "\(state.snapshot.pullRequests.count)")
            StatTile(
                label: "Ready",
                value: "\(state.mergeablePullRequests.count)",
                tint: state.mergeablePullRequests.isEmpty ? nil : palette.positive
            )
            StatTile(
                label: "Blocked",
                value: "\(blocked.count)",
                tint: blocked.isEmpty ? nil : palette.warning,
                detail: conflictCount > 0 ? "\(conflictCount) conflicting" : nil
            )
        }
    }

    private var conflictCount: Int {
        state.snapshot.pullRequests.filter { $0.readiness == .conflicting }.count
    }

    @ViewBuilder
    private func group(_ title: String, _ pullRequests: [PullRequestSummary]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            SectionHeader(title) {
                Text("\(pullRequests.count)")
                    .font(Typeface.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(pullRequests) { pullRequest in
                PullRequestCard(pullRequest: pullRequest)
            }
        }
    }
}

private struct PullRequestCard: View {
    let pullRequest: PullRequestSummary

    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(pullRequest.title)
                            .font(Typeface.body)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text("#\(pullRequest.number)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                            Text(pullRequest.authorLogin)
                                .lineLimit(1)
                            Text("·")
                            Text(RelativeTime.ago(pullRequest.createdAt))
                        }
                        .font(Typeface.footnote)
                        .foregroundStyle(palette.textTertiary)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    if pullRequest.isDraft {
                        Pill(text: "draft", tint: palette.textTertiary)
                    }
                    if pullRequest.readiness == .conflicting {
                        Pill(text: "conflicts", tint: palette.warning, icon: "exclamationmark")
                    }
                    if pullRequest.readiness == .unknown && !pullRequest.isDraft {
                        Pill(text: "checking", tint: palette.textTertiary)
                    }

                    Spacer(minLength: 0)

                    if state.isBusy(pullRequest: pullRequest.number) {
                        ProgressView().controlSize(.small).tint(palette.textSecondary)
                    } else if pullRequest.canMerge {
                        mergeButton
                    }
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { openURL(pullRequest.url) }
    }

    /// A button rather than a swipe action. The swipe was invisible — nothing
    /// on the row said it existed — and the thing it did deploys six hosts, so
    /// it should be something you can see before you do it. Face ID still sits
    /// in front, and the label says what merging actually causes.
    private var mergeButton: some View {
        Button {
            Task { await state.merge(pullRequest) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .bold))
                Text("Squash · deploys")
                    .font(Typeface.footnote)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(palette.accentMuted)
            )
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        if pullRequest.isDraft { return "circle.dashed" }
        return pullRequest.readiness == .conflicting
            ? "exclamationmark.triangle"
            : "arrow.trianglehead.pull"
    }

    private var tint: Color {
        if pullRequest.isDraft { return palette.textTertiary }
        switch pullRequest.readiness {
        case .mergeable: return palette.positive
        case .conflicting: return palette.warning
        case .unknown: return palette.textSecondary
        }
    }
}
