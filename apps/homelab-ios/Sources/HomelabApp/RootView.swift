import HomelabCore
import SwiftUI

private enum AppTab: String {
    case home, pulls, health, logs
}

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: AppTab = .home

    var body: some View {
        content
            // One line wires the whole palette: every view below reads
            // `\.palette` and none of them knows which appearance it is in.
            .homelabPalette(colorScheme)
            .tint(Palette.forScheme(colorScheme).accent)
            .onOpenURL { url in
                guard url.scheme == "homelab" else { return }
                switch url.host {
                case "home": selectedTab = .home
                case "pull-requests": selectedTab = .pulls
                case "health": selectedTab = .health
                case "logs": selectedTab = .logs
                default: break
                }
            }

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
                SignedInView(state: state, selection: $selectedTab)
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
    @Binding var selection: AppTab

    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "square.grid.2x2", value: .home) {
                NavigationStack { HomeView() }
            }
            Tab("Pull requests", systemImage: "arrow.trianglehead.pull", value: .pulls) {
                NavigationStack { PullRequestsView() }
            }
            Tab("Health", systemImage: "waveform.path.ecg", value: .health) {
                NavigationStack { HealthView() }
            }
            Tab("Logs", systemImage: "doc.text.magnifyingglass", value: .logs) {
                NavigationStack { LogsView() }
            }
        }
        .environment(state)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            state.start()
            await session.refresh()
        }
        // A grant revoked on github.com shows up as a 401 on the next poll;
        // drop to sign-in rather than sitting behind a permanent error.
        .onChange(of: state.lastFailure) { _, failure in
            Task { await session.handleIfUnauthenticated(failure) }
        }
    }
}
