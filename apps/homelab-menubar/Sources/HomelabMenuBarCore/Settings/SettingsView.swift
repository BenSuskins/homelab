import HomelabCore
import SwiftUI

/// The app's settings window. Sections are the extension point: a new group of
/// options is a new `Section` here, and only becomes a tabbed `TabView` if the
/// list ever outgrows one screen.
public struct SettingsView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Form {
            Section("General") {
                launchAtLogin
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var launchAtLogin: some View {
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
    }
}
