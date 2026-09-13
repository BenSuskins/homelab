import Foundation
import HomelabCore
import Observation

/// Owns "are we signed in", and nothing else. `AppState` is built only once
/// there is a token, so no view below the root has to cope with a client that
/// cannot authenticate.
@MainActor
@Observable
final class Session {
    enum Phase: Equatable {
        case checking
        case signedOut(message: String?)
        /// Waiting for the user to type the code into github.com on any device.
        case awaitingAuthorisation(DeviceCodeGrant)
        case signedIn
    }

    private(set) var phase: Phase = .checking
    private(set) var appState: AppState?
    private(set) var healthMonitor = HealthMonitor()

    private let tokens: any TokenStoring
    private let flow: DeviceFlow
    private var pollingTask: Task<Void, Never>?

    init(
        tokens: any TokenStoring = KeychainTokenStore(
            service: AppConfiguration.keychainService,
            accessGroup: AppConfiguration.keychainAccessGroup
        ),
        flow: DeviceFlow = DeviceFlow(clientID: AppConfiguration.gitHubClientID)
    ) {
        self.tokens = tokens
        self.flow = flow
    }

    func restore() async {
        guard await tokens.token() != nil else {
            phase = .signedOut(message: nil)
            return
        }
        activate()
    }

    func signIn() {
        guard AppConfiguration.isConfigured else {
            phase = .signedOut(
                message: "No OAuth client ID — set AppConfiguration.gitHubClientID."
            )
            return
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let grant = try await flow.requestCode()
                phase = .awaitingAuthorisation(grant)
                let token = try await flow.awaitToken(for: grant)
                try await tokens.save(token)
                activate()
            } catch let failure as DeviceFlowFailure {
                phase = .signedOut(message: failure.displayMessage)
            } catch {
                phase = .signedOut(message: error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        phase = .signedOut(message: nil)
    }

    func signOut() async {
        pollingTask?.cancel()
        appState?.stop()
        appState = nil
        try? await tokens.clear()
        phase = .signedOut(message: nil)
    }

    /// A 401 mid-session means the grant was revoked on github.com. Drop
    /// straight back to sign-in rather than sitting behind a permanent error
    /// banner that no amount of retrying will clear.
    func handleIfUnauthenticated(_ failure: GitHubFailure?) async {
        guard case .signedIn = phase, failure?.requiresReauthentication == true else { return }
        await signOut()
    }

    private func activate() {
        appState = AppState(
            client: GitHubClient(transport: URLSessionTransport(tokens: tokens)),
            cache: SnapshotCache(appGroup: AppConfiguration.appGroup),
            // No notifier: a suspended iOS app never sees the failure, so the
            // widget is the ambient signal instead. See ADR-0005.
            notifier: SilentFailureNotifier(),
            writeAuthorisation: BiometricWriteAuthorisation()
        )
        phase = .signedIn
    }
}
