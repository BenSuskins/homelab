import HomelabCore
import SwiftUI

struct PullRequestRowView: View {
    let pullRequest: PullRequestSummary

    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pullRequest.isDraft ? "circle.dashed" : "arrow.trianglehead.pull")
                .foregroundStyle(pullRequest.isDraft ? Color.secondary : (pullRequest.readiness == .conflicting ? Color.orange : Color.secondary))
                .frame(width: 16)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(value: pullRequest)
            } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(pullRequest.number) \(pullRequest.title)")
                    .font(.callout)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            }
            .buttonStyle(.plain)
            .help("Read pull request #\(pullRequest.number)")

            Spacer(minLength: 4)

            if state.isBusy(pullRequest: pullRequest.number) {
                ProgressView().controlSize(.small)
            } else if pullRequest.canMerge {
                Button("Merge") {
                    Task { await state.merge(pullRequest) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Squash merge #\(pullRequest.number). Starts deployment.")
                .help("Squash merge #\(pullRequest.number) — starts the deployment")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
