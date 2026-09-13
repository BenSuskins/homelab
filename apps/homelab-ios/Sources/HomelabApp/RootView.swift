import HomelabCore
import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.phase {
        case .checking:
            ProgressView()
        case .signedOut(let message):
            SignInView(message: message)
        case .awaitingAuthorisation(let grant):
            DeviceCodeView(grant: grant)
        case .signedIn:
            if let state = session.appState {
                SignedInView(state: state)
            } else {
                ProgressView()
            }
        }
    }
}

private struct SignedInView: View {
    let state: AppState

    @Environment(Session.self) private var session

    var body: some View {
        TabView {
            Tab("Runs", systemImage: "play.rectangle") {
                NavigationStack { RunsView() }
            }
            Tab("Pull requests", systemImage: "arrow.trianglehead.pull") {
                NavigationStack { PullRequestsView() }
            }
            Tab("Health", systemImage: "waveform.path.ecg") {
                NavigationStack { HealthView() }
            }
        }
        .environment(state)
        .task { state.start() }
        // A grant revoked on github.com shows up as a 401 on the next poll;
        // drop to sign-in rather than sitting behind a permanent error.
        .onChange(of: state.lastFailure) { _, failure in
            Task { await session.handleIfUnauthenticated(failure) }
        }
    }
}
