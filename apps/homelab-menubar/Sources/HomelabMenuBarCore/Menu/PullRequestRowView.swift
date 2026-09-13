import HomelabCore
import SwiftUI

struct PullRequestRowView: View {
    let pullRequest: PullRequestSummary

    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pullRequest.isDraft ? "circle.dashed" : "arrow.trianglehead.pull")
                .foregroundStyle(pullRequest.isDraft ? Color.secondary : Color.green)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text("#\(pullRequest.number) \(pullRequest.title)")
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if state.isBusy(pullRequest: pullRequest.number) {
                ProgressView().controlSize(.small)
            } else if pullRequest.canMerge {
                Button("Merge") {
                    Task { await state.merge(pullRequest) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Squash merge — this deploys")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture { openURL(pullRequest.url) }
    }

    private var subtitle: String {
        var parts = [pullRequest.authorLogin, RelativeTime.ago(pullRequest.createdAt)]
        if pullRequest.isDraft {
            parts.append("draft")
        } else if pullRequest.readiness == .conflicting {
            parts.append("conflicts")
        }
        return parts.joined(separator: " · ")
    }
}
