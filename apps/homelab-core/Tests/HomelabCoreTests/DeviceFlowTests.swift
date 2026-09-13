import Foundation
import Testing
@testable import HomelabCore

/// `.serialized` is load-bearing: `ScriptedURLProtocol` queues its responses in
/// static storage, and swift-testing runs tests in parallel by default. Two
/// tests draining one queue means somebody gets `{}`, which is neither a token
/// nor an error — so `awaitToken` treats it as "still pending" and spins until
/// the grant expires. That hung CI for seven minutes before it was spotted.
///
/// `.timeLimit` is the backstop: if that ever recurs it fails in a minute with
/// a name attached, instead of looking like a slow runner.
@Suite("Device flow", .serialized, .timeLimit(.minutes(1)))
struct DeviceFlowTests {
    private func flow(_ session: URLSession) -> DeviceFlow {
        DeviceFlow(
            clientID: "Iv1.test",
            session: session,
            authRoot: URL(string: "https://github.test")!
        )
    }

    @Test("asks for a code and reports what the user must type")
    func requestsCode() async throws {
        let session = ScriptedURLProtocol.session(responses: ["""
        {
          "device_code": "dc-123",
          "user_code": "WDJB-MJHT",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 900,
          "interval": 5
        }
        """])

        let grant = try await flow(session).requestCode()

        #expect(grant.userCode == "WDJB-MJHT")
        #expect(grant.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(grant.interval == .seconds(5))
        #expect(grant.expiresAt > Date())
    }

    @Test("keeps polling while GitHub says the user has not finished yet")
    func pollsThroughPending() async throws {
        let session = ScriptedURLProtocol.session(responses: [
            #"{"error":"authorization_pending"}"#,
            #"{"error":"authorization_pending"}"#,
            #"{"access_token":"ghu_abc","token_type":"bearer"}"#,
        ])

        let token = try await flow(session).awaitToken(for: grant(), sleep: { _ in })

        #expect(token == "ghu_abc")
    }

    @Test("widens the interval when told to slow down rather than treating it as an error")
    func honoursSlowDown() async throws {
        let session = ScriptedURLProtocol.session(responses: [
            #"{"error":"slow_down","interval":10}"#,
            #"{"access_token":"ghu_abc"}"#,
        ])

        let recorder = SleepRecorder()
        let token = try await flow(session).awaitToken(
            for: grant(interval: .seconds(5)),
            sleep: { await recorder.record($0) }
        )

        #expect(token == "ghu_abc")
        // Ignoring slow_down is how a device flow gets itself rate-limited.
        #expect(await recorder.intervals == [.seconds(5), .seconds(10)])
    }

    @Test("reports a declined authorisation distinctly from an expiry")
    func reportsDenial() async {
        let session = ScriptedURLProtocol.session(responses: [#"{"error":"access_denied"}"#])

        await #expect(throws: DeviceFlowFailure.declinedByUser) {
            try await flow(session).awaitToken(for: grant(), sleep: { _ in })
        }
    }

    @Test("reports an expired device code")
    func reportsExpiry() async {
        let session = ScriptedURLProtocol.session(responses: [#"{"error":"expired_token"}"#])

        await #expect(throws: DeviceFlowFailure.expired) {
            try await flow(session).awaitToken(for: grant(), sleep: { _ in })
        }
    }

    @Test("stops once the grant's own deadline has passed")
    func stopsAtDeadline() async {
        let session = ScriptedURLProtocol.session(responses: [#"{"error":"authorization_pending"}"#])

        await #expect(throws: DeviceFlowFailure.expired) {
            try await flow(session).awaitToken(
                for: grant(expiresAt: Date(timeIntervalSince1970: 0)),
                sleep: { _ in }
            )
        }
    }

    @Test("asks for the scopes the app actually needs and no others")
    func requestsMinimumViableScope() {
        // Device flow can only issue classic scopes, so this string is the
        // whole of the grant's blast radius — see ADR-0004.
        #expect(DeviceFlow.scope == "repo workflow")
    }

    private func grant(
        interval: Duration = .seconds(1),
        expiresAt: Date = Date().addingTimeInterval(900)
    ) -> DeviceCodeGrant {
        DeviceCodeGrant(
            userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresAt: expiresAt,
            deviceCode: "dc-123",
            interval: interval
        )
    }
}

actor SleepRecorder {
    var intervals: [Duration] = []
    func record(_ interval: Duration) { intervals.append(interval) }
}

/// Answers each request with the next canned body, so a poll loop can be walked
/// through pending → success without a real network or a real wait.
final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queued: [String] = []

    static func session(responses: [String]) -> URLSession {
        lock.withLock { queued = responses }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// An exhausted script answers with an unrecognised error rather than `{}`.
    /// `{}` is indistinguishable from "still pending", so the poll loop would
    /// spin on it until the grant expired; an unknown error code throws
    /// immediately and names itself in the failure.
    private static func next() -> String {
        lock.withLock {
            queued.isEmpty
                ? #"{"error":"test_script_exhausted"}"#
                : queued.removeFirst()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.next().utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
