import HomelabCore
import SwiftUI

/// Switches on whether there is a token. Since ADR-0004 was amended this app
/// holds one of its own, so "signed out" is a state the menu has to render —
/// it never was while `gh` carried the credential.
public struct MenuView: View {
    @Environment(Session.self) private var session

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch session.phase {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            case .signedOut(let message):
                SignInPanel(message: message)
            case .awaitingAuthorisation(let grant):
                DeviceCodePanel(grant: grant)
            case .signedIn:
                if let state = session.appState {
                    SignedInMenu().environment(state)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 340)
        .frame(maxHeight: 720)
    }
}

struct SignedInMenu: View {
    @Environment(AppState.self) private var state
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            if state.snapshot.lastRefreshedAt == nil {
                Label("Waiting for GitHub status", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
            }
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
                Button("Retry") { Task { await state.refresh() } }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
            }

            Divider().padding(.vertical, 6)
            footer
        }
        .task { state.start() }
        // A grant revoked on github.com surfaces as a 401 on the next poll.
        .onChange(of: state.lastFailure) { _, failure in
            Task { await session.handleIfUnauthenticated(failure) }
        }
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

            if state.snapshot.lastRefreshedAt == nil {
                Text("Waiting for GitHub")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            } else if state.snapshot.pullRequests.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.snapshot.pullRequests.prefix(6)) { pullRequest in
                            PullRequestRowView(pullRequest: pullRequest)
                        }
                    }
                }
                .frame(maxHeight: 230)

                if state.snapshot.pullRequests.count > 6 {
                    Link(destination: state.repository.browserURL.appendingPathComponent("pulls")) {
                        Text("View all \(state.snapshot.pullRequests.count) on GitHub")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
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

struct SignInPanel: View {
    let message: String?

    @Environment(Session.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Homelab")
                .font(.headline)

            Text("Sign in with GitHub to see the workflows and merge pull requests.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Sign in with GitHub") {
                    session.signIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!session.configuration.isConfigured)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !session.configuration.isConfigured {
                Text("GitHub sign in is not configured for this build.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }
}

struct DeviceCodePanel: View {
    let grant: DeviceCodeGrant

    @Environment(Session.self) private var session
    @State private var hasCopied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter this code on GitHub")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(grant.userCode)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary, in: .rect(cornerRadius: 8))

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(grant.userCode, forType: .string)
                    hasCopied = true
                } label: {
                    Label(hasCopied ? "Copied" : "Copy code", systemImage: hasCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    openURL(grant.verificationURL)
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for authorisation…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    session.cancelSignIn()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }
}
