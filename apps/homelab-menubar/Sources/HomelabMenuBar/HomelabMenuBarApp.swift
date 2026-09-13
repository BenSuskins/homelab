import HomelabCore
import HomelabMenuBarCore
import SwiftUI

@main
struct HomelabMenuBarApp: App {
    /// One sign-in path with iOS, per the amendment to ADR-0004. `gh` used to
    /// be this app's whole credential story; it now holds an OAuth token like
    /// the phone does, which is what removed the two-transport split — and the
    /// `PATH`-hunting that a GUI app needed to find `gh` at all.
    @State private var session = Session(
        configuration: .macOS,
        tokens: KeychainTokenStore(service: HomelabConfiguration.macOS.keychainService),
        cache: SnapshotCache(),
        notifier: FailureNotifier(),
        loginItem: LoginItemService()
    )

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(session)
                .task { await session.restore() }
        } label: {
            Image(systemName: glyphName)
                .symbolRenderingMode(isFailed ? .multicolor : .monochrome)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(session)
        }
    }

    /// Signed out, the glyph is the app's own state rather than the lab's —
    /// there is nothing to report until there is a token.
    private var glyphName: String {
        guard let state = session.appState else { return "server.rack" }
        return state.snapshot.glyph.symbolName
    }

    private var isFailed: Bool {
        session.appState?.snapshot.glyph == .failed
    }
}
