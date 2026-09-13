import HomelabCore
import HomelabMenuBarCore
import SwiftUI

@main
struct HomelabMenuBarApp: App {
    /// `GhCommandTransport` is what keeps this app's original property intact:
    /// it holds no credential, and `gh auth login` is the whole of its
    /// credential management. The iOS app cannot do this, which is why the
    /// transport is a seam at all — see ADR-0004.
    @State private var state = AppState(
        client: GitHubClient(transport: GhCommandTransport()),
        notifier: FailureNotifier(),
        loginItem: LoginItemService()
    )

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(state)
        } label: {
            Image(systemName: state.snapshot.glyph.symbolName)
                .symbolRenderingMode(state.snapshot.glyph == .failed ? .multicolor : .monochrome)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhaseHasStarted, initial: true) { _, _ in
            state.start()
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }

    /// `MenuBarExtra` has no scene phase of its own; this exists purely to give
    /// `onChange(initial:)` something to fire against exactly once at launch.
    private var scenePhaseHasStarted: Bool { true }
}
