import HomelabCore
import SwiftUI

/// The app's settings window. Sections are the extension point: a new group of
/// options is a new `Section` here, and only becomes a tabbed `TabView` if the
/// list ever outgrows one screen.
public struct SettingsView: View {
    @Environment(Session.self) private var session

    public init() {}

    public var body: some View {
        Form {
            Section("General") {
                launchAtLogin
            }

            Section("GitHub") {
                account
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var account: some View {
        if session.isSignedIn {
            VStack(alignment: .leading, spacing: 6) {
                Text("Signed in with a GitHub device-flow token.")
                Text("Stored in your Keychain. Revoke it from GitHub → Settings → Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Sign out") {
                    Task { await session.signOut() }
                }
                .controlSize(.small)
            }
        } else {
            Text("Not signed in. Open the menu to sign in.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        if let state = session.appState {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { state.launchesAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at login")
                    Text("Start Homelab automatically when you log in.")
                }

                if let hint = state.launchAtLoginHint {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(hint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)

                    Button("Open Login Items…") {
                        state.openLoginItemSettings()
                    }
                    .controlSize(.small)
                }
            }
        } else {
            Text("Sign in to change this.")
                .foregroundStyle(.secondary)
        }
    }
}
