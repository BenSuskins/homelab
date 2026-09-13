import HomelabCore
import SwiftUI

public struct MenuView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            ForEach(state.snapshot.runRows) { row in
                RunRowView(row: row)
            }

            Divider().padding(.vertical, 6)
            pullRequestSection

            Divider().padding(.vertical, 6)
            quickLinkSection

            if let errorMessage = state.snapshot.errorMessage {
                Divider().padding(.vertical, 6)
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            Divider().padding(.vertical, 6)
            footer
        }
        .padding(.vertical, 8)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Homelab")
                .font(.headline)
            Spacer()
            if state.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
    }

    private var pullRequestSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Open PRs (\(state.snapshot.pullRequests.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            if state.snapshot.pullRequests.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            } else {
                ForEach(state.snapshot.pullRequests) { pullRequest in
                    PullRequestRowView(pullRequest: pullRequest)
                }
            }
        }
    }

    private var quickLinkSection: some View {
        HStack(spacing: 4) {
            ForEach(state.quickLinks) { link in
                Button {
                    openURL(link.url)
                } label: {
                    Label(link.title, systemImage: link.symbolName)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10)
    }

    private var footer: some View {
        HStack {
            if let lastRefreshedAt = state.snapshot.lastRefreshedAt {
                Text("Updated \(RelativeTime.ago(lastRefreshedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Refresh") {
                Task { await state.refresh() }
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            // An `LSUIElement` app is never frontmost, so the settings window
            // opens behind everything unless the app is activated by hand.
            SettingsLink {
                Text("Settings")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }
}
