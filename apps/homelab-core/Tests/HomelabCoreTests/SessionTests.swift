import Foundation
import Testing
@testable import HomelabCore

/// The regression these exist for: the app asked for a fresh sign-in roughly
/// once a day. The OAuth device flow issues no refresh token and the access
/// token does not expire, so nothing on GitHub's side was ending the session —
/// the app was deleting its own Keychain item whenever a poll could not read
/// it, which is every poll that overlaps the screen locking.
@Suite("Session")
@MainActor
struct SessionTests {
    private func makeSession(
        token: String?,
        transport: FakeTransport = FakeTransport()
    ) -> (Session, InMemoryTokenStore) {
        let tokens = InMemoryTokenStore(token: token)
        let session = Session(
            configuration: .iOS,
            tokens: tokens,
            cache: SnapshotCache(
                fileURL: URL.temporaryDirectory
                    .appendingPathComponent("session-\(UUID().uuidString).json")
            ),
            transport: transport
        )
        return (session, tokens)
    }

    @Test("keeps the token when the Keychain could not be read")
    func survivesAnUnreadableKeychain() async {
        let (session, tokens) = makeSession(token: "gho_stored")
        await session.restore()
        #expect(session.isSignedIn)

        await session.handleIfUnauthenticated(.credentialUnavailable)

        #expect(session.isSignedIn)
        let stored = await tokens.token()
        #expect(stored == "gho_stored")
    }

    @Test("signs out when GitHub rejects the credential")
    func signsOutOnRejectedCredential() async {
        let (session, tokens) = makeSession(token: "gho_revoked")
        await session.restore()

        await session.handleIfUnauthenticated(.notAuthenticated)

        #expect(session.isSignedIn == false)
        let stored = await tokens.token()
        #expect(stored == nil)
    }

    @Test("leaves the token alone for every other failure")
    func ignoresUnrelatedFailures() async {
        let (session, tokens) = makeSession(token: "gho_stored")
        await session.restore()

        for failure: GitHubFailure in [
            .transportUnavailable("offline"),
            .requestFailed(status: 500, message: "server error"),
            .malformedResponse("x"),
        ] {
            await session.handleIfUnauthenticated(failure)
        }

        #expect(session.isSignedIn)
        let stored = await tokens.token()
        #expect(stored == "gho_stored")
    }

    @Test("an explicit sign out still clears the token")
    func explicitSignOutClears() async {
        let (session, tokens) = makeSession(token: "gho_stored")
        await session.restore()

        await session.signOut()

        #expect(session.isSignedIn == false)
        let stored = await tokens.token()
        #expect(stored == nil)
    }
}

@Suite("URLSessionTransport credentials")
struct URLSessionTransportCredentialTests {
    /// Reports "cannot read the credential", not "not authenticated" — and
    /// never reaches the network to find out, so the assertion holds offline.
    @Test("distinguishes an unreadable credential from a rejected one")
    func unreadableTokenIsNotARejection() async {
        let transport = URLSessionTransport(tokens: InMemoryTokenStore(token: nil))

        await #expect(throws: GitHubFailure.credentialUnavailable) {
            try await transport.send(.get("user"))
        }
        #expect(GitHubFailure.credentialUnavailable.requiresReauthentication == false)
    }
}
