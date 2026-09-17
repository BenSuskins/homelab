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
    /// Shown under the spinner on the device-code screen while a poll is
    /// failing. Not an error: the grant is still live and still being polled,
    /// and the screen says so rather than going quiet.
    public private(set) var authorisationNotice: String?
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
    /// Injected only by tests, which have no business reaching
    /// `api.github.com`; production builds get `URLSessionTransport`.
    private let transport: (any GitHubTransport)?
    private var pollingTask: Task<Void, Never>?
    private var lastResumeAt: Date?

    public init(
        configuration: HomelabConfiguration,
        tokens: any TokenStoring,
        cache: SnapshotCache,
        notifier: any FailureNotifying = SilentFailureNotifier(),
        loginItem: any LoginItemControlling = UnsupportedLoginItemService(),
        writeAuthorisation: any WriteAuthorising = AlwaysAuthorised(),
        healthMonitor: HealthMonitor = HealthMonitor(),
        logMonitor: LogMonitor = LogMonitor(),
        flow: DeviceFlow? = nil,
        transport: (any GitHubTransport)? = nil
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
        self.transport = transport
    }

    public var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    public func restore() async {
        // Only ever runs the once. A scene that reconnects re-fires the `.task`
        // that calls this, and without the guard that would wipe a device-code
        // screen the user is part-way through.
        guard case .checking = phase else { return }

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
        authorisationNotice = nil
        lastResumeAt = nil
        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let grant = try await flow.requestCode()
                phase = .awaitingAuthorisation(grant)
                try await awaitAuthorisation(of: grant)
            } catch let failure as DeviceFlowFailure {
                abandonSignIn(with: failure.displayMessage)
            } catch {
                abandonSignIn(with: error.localizedDescription)
            }
        }
    }

    /// Picks a device-code flow back up after the app was away.
    ///
    /// Leaving for Safari to type the code in is the *expected* path through
    /// this screen, and iOS suspends us seconds later — which stops the polling
    /// task mid-sleep and kills whatever request was in flight. The grant is
    /// good for fifteen minutes, so coming back to the foreground restarts the
    /// poll on the same grant rather than starting the user over.
    public func resumeSignIn() {
        guard case .awaitingAuthorisation(let grant) = phase else { return }
        guard Date() < grant.expiresAt else {
            phase = .signedOut(message: DeviceFlowFailure.expired.displayMessage)
            return
        }

        // `.active` fires for a swipe at Control Centre too. Restarting the
        // poll every time would poll GitHub as fast as the user can flick
        // between apps, and GitHub answers that with `slow_down`.
        if let lastResumeAt, Date().timeIntervalSince(lastResumeAt) < 5 { return }
        lastResumeAt = Date()

        pollingTask?.cancel()
        authorisationNotice = nil
        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // No opening delay: you came back to this screen because you
                // just finished authorising on the other one.
                try await awaitAuthorisation(of: grant, firstDelay: .zero)
            } catch let failure as DeviceFlowFailure {
                abandonSignIn(with: failure.displayMessage)
            } catch {
                abandonSignIn(with: error.localizedDescription)
            }
        }
    }

    public func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        authorisationNotice = nil
        phase = .signedOut(message: nil)
    }

    private func awaitAuthorisation(
        of grant: DeviceCodeGrant,
        firstDelay: Duration? = nil
    ) async throws {
        let token = try await flow.awaitToken(
            for: grant,
            firstDelay: firstDelay,
            onTransientFailure: { [weak self] failure in
                // Hops rather than isolates: `awaitToken` is nonisolated and
                // may call this from whichever executor the poll landed on.
                Task { @MainActor in
                    self?.authorisationNotice = failure.displayMessage
                }
            }
        )
        authorisationNotice = nil
        try await tokens.save(token)
        activate()
    }

    /// Ends the flow and says why — unless this task was cancelled, in which
    /// case either `cancelSignIn` has already decided what the screen says or
    /// `resumeSignIn` has already replaced us with a fresh poll.
    private func abandonSignIn(with message: String) {
        authorisationNotice = nil
        guard !Task.isCancelled else { return }
        pollingTask = nil
        phase = .signedOut(message: message)
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
    ///
    /// `credentialUnavailable` deliberately does *not* land here. The Keychain
    /// item is `WhenUnlockedThisDeviceOnly`, so a poll that overlaps the screen
    /// locking reads nothing — and signing out on that wipes the token, which
    /// is why the app used to ask for a fresh sign-in roughly once a day.
    public func handleIfUnauthenticated(_ failure: GitHubFailure?) async {
        guard isSignedIn, failure?.requiresReauthentication == true else { return }
        await signOut()
    }

    private func activate() {
        let client = GitHubClient(transport: transport ?? URLSessionTransport(tokens: tokens))
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
