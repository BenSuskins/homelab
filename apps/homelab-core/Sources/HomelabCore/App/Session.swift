import Foundation
import Observation

/// Owns "are we signed in", and nothing else. `AppState` is built only once
/// there is a token, so no view below the root has to cope with a client that
/// cannot authenticate.
///
/// Shared by both apps since ADR-0004 was amended: macOS stopped shelling out
/// to `gh` and now holds a token of its own, so there is one sign-in path
/// rather than two credential stories.
@MainActor
@Observable
public final class Session {
    public enum Phase: Equatable {
        case checking
        case signedOut(message: String?)
        /// Waiting for the user to type the code into github.com on any device.
        case awaitingAuthorisation(DeviceCodeGrant)
        case signedIn
    }

    public private(set) var phase: Phase = .checking
    public private(set) var appState: AppState?
    /// Who the token belongs to. Nil until the first read lands, which is fine:
    /// the profile button falls back to a glyph, so nothing waits on it.
    public private(set) var viewer: GitHubViewer?
    public private(set) var healthMonitor: HealthMonitor
    public private(set) var logMonitor: LogMonitor

    public let configuration: HomelabConfiguration

    private let tokens: any TokenStoring
    private let flow: DeviceFlow
    private let cache: SnapshotCache
    private let notifier: any FailureNotifying
    private let loginItem: any LoginItemControlling
    private let writeAuthorisation: any WriteAuthorising
    private var pollingTask: Task<Void, Never>?

    public init(
        configuration: HomelabConfiguration,
        tokens: any TokenStoring,
        cache: SnapshotCache,
        notifier: any FailureNotifying = SilentFailureNotifier(),
        loginItem: any LoginItemControlling = UnsupportedLoginItemService(),
        writeAuthorisation: any WriteAuthorising = AlwaysAuthorised(),
        healthMonitor: HealthMonitor = HealthMonitor(),
        logMonitor: LogMonitor = LogMonitor(),
        flow: DeviceFlow? = nil
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.cache = cache
        self.notifier = notifier
        self.loginItem = loginItem
        self.writeAuthorisation = writeAuthorisation
        self.healthMonitor = healthMonitor
        self.logMonitor = logMonitor
        self.flow = flow ?? DeviceFlow(clientID: configuration.gitHubClientID)
    }

    public var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    public func restore() async {
        guard await tokens.token() != nil else {
            phase = .signedOut(message: nil)
            return
        }
        activate()
    }

    public func signIn() {
        guard configuration.isConfigured else {
            phase = .signedOut(
                message: "No OAuth client ID — set HomelabConfiguration.gitHubClientID."
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

    public func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        phase = .signedOut(message: nil)
    }

    public func signOut() async {
        pollingTask?.cancel()
        appState?.stop()
        appState = nil
        viewer = nil
        try? await tokens.clear()
        phase = .signedOut(message: nil)
    }

    /// A 401 mid-session means the grant was revoked on github.com. Drop
    /// straight back to sign-in rather than sitting behind a permanent error
    /// banner that no amount of retrying will clear.
    public func handleIfUnauthenticated(_ failure: GitHubFailure?) async {
        guard isSignedIn, failure?.requiresReauthentication == true else { return }
        await signOut()
    }

    private func activate() {
        let client = GitHubClient(transport: URLSessionTransport(tokens: tokens))
        appState = AppState(
            client: client,
            cache: cache,
            notifier: notifier,
            loginItem: loginItem,
            writeAuthorisation: writeAuthorisation
        )
        phase = .signedIn

        // Fire and forget: the account's name and avatar are decoration on a
        // button, so a failure here must not hold up a session that is
        // otherwise perfectly usable.
        Task { [weak self] in
            let viewer = try? await client.viewer()
            self?.viewer = viewer
        }
    }
}
