import Foundation

/// What to show the user while they authorise the app on another screen.
public struct DeviceCodeGrant: Sendable, Equatable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    let deviceCode: String
    let interval: Duration

    public init(
        userCode: String,
        verificationURL: URL,
        expiresAt: Date,
        deviceCode: String,
        interval: Duration
    ) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.deviceCode = deviceCode
        self.interval = interval
    }
}

public enum DeviceFlowFailure: Error, Equatable, Sendable {
    case network(String)
    case expired
    case declinedByUser
    case malformedResponse(String)
    case server(String)

    public var displayMessage: String {
        switch self {
        case .network(let detail): detail.isEmpty ? "Cannot reach GitHub" : detail
        case .expired: "The code expired — start again"
        case .declinedByUser: "Access was declined on GitHub"
        case .malformedResponse: "Unexpected response from GitHub"
        case .server(let detail): detail
        }
    }
}

/// GitHub's OAuth device flow. Chosen over a pasted token because it needs no
/// client secret and therefore no server of our own, and because the resulting
/// grant is revocable from GitHub's own UI without touching the device.
///
/// The scope is the honest cost, recorded in ADR-0004: device flow issues
/// classic scopes only, so `repo workflow` reaches every repository on the
/// account. Biometrics on writes are what offsets it.
public struct DeviceFlow: Sendable {
    public static let scope = "repo workflow"

    private let clientID: String
    private let session: URLSession
    private let authRoot: URL

    public init(
        clientID: String,
        session: URLSession = .shared,
        authRoot: URL = URL(string: "https://github.com")!
    ) {
        self.clientID = clientID
        self.session = session
        self.authRoot = authRoot
    }

    public func requestCode() async throws(DeviceFlowFailure) -> DeviceCodeGrant {
        let payload: DeviceCodePayload = try await post(
            path: "login/device/code",
            fields: ["client_id": clientID, "scope": Self.scope]
        )

        guard let url = URL(string: payload.verificationUri) else {
            throw .malformedResponse("verification_uri was not a URL")
        }

        return DeviceCodeGrant(
            userCode: payload.userCode,
            verificationURL: url,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            deviceCode: payload.deviceCode,
            // GitHub's floor is 5s; honour whatever it actually asked for.
            interval: .seconds(max(1, payload.interval))
        )
    }

    /// Polls until GitHub says yes, no, or too late. `slow_down` is not an
    /// error — GitHub uses it to widen the interval mid-flow, and ignoring it
    /// gets the request rate-limited.
    public func awaitToken(
        for grant: DeviceCodeGrant,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws(DeviceFlowFailure) -> String {
        var interval = grant.interval

        while true {
            if Date() >= grant.expiresAt { throw .expired }

            do {
                try await sleep(interval)
            } catch {
                throw .network("Cancelled")
            }

            let payload: AccessTokenPayload = try await post(
                path: "login/oauth/access_token",
                fields: [
                    "client_id": clientID,
                    "device_code": grant.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ]
            )

            if let token = payload.accessToken { return token }

            switch payload.error {
            case "authorization_pending", nil:
                continue
            case "slow_down":
                interval += .seconds(5)
            case "expired_token":
                throw .expired
            case "access_denied":
                throw .declinedByUser
            case .some(let other):
                throw .server(payload.errorDescription ?? other)
            }
        }
    }

    // MARK: Plumbing

    private func post<Value: Decodable>(
        path: String,
        fields: [String: String]
    ) async throws(DeviceFlowFailure) -> Value {
        var request = URLRequest(url: authRoot.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(fields)
        } catch {
            throw .malformedResponse(String(describing: error))
        }

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw .network((error as NSError).localizedDescription)
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw .malformedResponse(String(describing: error))
        }
    }

    private struct DeviceCodePayload: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct AccessTokenPayload: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error
            case errorDescription = "error_description"
        }
    }
}
