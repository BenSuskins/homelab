import HomelabCore
import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            // One line wires the whole palette: every view below reads
            // `\.palette` and none of them knows which appearance it is in.
            .homelabPalette(colorScheme)
            .tint(Palette.forScheme(colorScheme).accent)
            // The layouts are dense grids of fixed sizes. Honouring Dynamic
            // Type past this point turns a two-line row into four and the
            // screen stops being scannable, which is the whole point of it.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .checking:
            LoadingScreen()
        case .signedOut(let message):
            SignInView(message: message)
        case .awaitingAuthorisation(let grant):
            DeviceCodeView(grant: grant)
        case .signedIn:
            if let state = session.appState {
                SignedInView(state: state)
            } else {
                LoadingScreen()
            }
        }
    }
}

private struct LoadingScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            ProgressView().tint(palette.textSecondary)
        }
    }
}

private struct SignedInView: View {
    let state: AppState

    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette

    var body: some View {
        TabView {
            Tab("Home", systemImage: "square.grid.2x2") {
                NavigationStack { HomeView() }
            }
            Tab("Pull requests", systemImage: "arrow.trianglehead.pull") {
                NavigationStack { PullRequestsView() }
            }
            Tab("Health", systemImage: "waveform.path.ecg") {
                NavigationStack { HealthView() }
            }
            Tab("Logs", systemImage: "doc.text.magnifyingglass") {
                NavigationStack { LogsView() }
            }
        }
        .environment(state)
        .toolbarBackground(palette.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { state.start() }
        // A grant revoked on github.com shows up as a 401 on the next poll;
        // drop to sign-in rather than sitting behind a permanent error.
        .onChange(of: state.lastFailure) { _, failure in
            Task { await session.handleIfUnauthenticated(failure) }
        }
    }
}
