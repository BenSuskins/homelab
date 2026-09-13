import HomelabCore
import SwiftUI

struct PullRequestsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if state.snapshot.pullRequests.isEmpty {
                ContentUnavailableView(
                    "No open pull requests",
                    systemImage: "checkmark.circle",
                    description: Text("Renovate will be along shortly.")
                )
            } else {
                ForEach(state.snapshot.pullRequests) { pullRequest in
                    row(for: pullRequest)
                }
            }
        }
        .navigationTitle("Pull requests")
        .refreshable { await state.refresh() }
    }

    private func row(for pullRequest: PullRequestSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pullRequest.isDraft ? "circle.dashed" : "arrow.trianglehead.pull")
                .foregroundStyle(pullRequest.isDraft ? Color.secondary : Color.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(pullRequest.number) \(pullRequest.title)")
                    .font(.callout)
                Text(subtitle(for: pullRequest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if state.isBusy(pullRequest: pullRequest.number) {
                ProgressView()
            }
        }
        .contentShape(.rect)
        .onTapGesture { openURL(pullRequest.url) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if pullRequest.canMerge {
                Button {
                    Task { await state.merge(pullRequest) }
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .tint(.green)
            }
        }
    }

    private func subtitle(for pullRequest: PullRequestSummary) -> String {
        var parts = [pullRequest.authorLogin, RelativeTime.ago(pullRequest.createdAt)]
        if pullRequest.isDraft {
            parts.append("draft")
        } else if pullRequest.readiness == .conflicting {
            parts.append("conflicts")
        }
        // Merging squashes to main, which starts Update Homelab. Worth saying
        // on the row rather than only in the biometric prompt.
        if pullRequest.canMerge {
            parts.append("swipe to merge · deploys")
        }
        return parts.joined(separator: " · ")
    }
}
