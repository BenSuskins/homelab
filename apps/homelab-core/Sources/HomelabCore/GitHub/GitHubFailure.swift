import Foundation

/// Why a GitHub call did not produce usable bytes. Deliberately transport
/// neutral: it survived `gh` being one of two transports, and then `gh` being
/// removed altogether, without a case changing.
public enum GitHubFailure: Error, Equatable, Sendable {
    /// The transport itself could not run — `gh` is not installed, or the
    /// device has no route to `api.github.com`.
    case transportUnavailable(String)
    /// GitHub rejected the credential: the grant has been revoked or expired,
    /// and no amount of retrying will fix it.
    case notAuthenticated
    /// We hold a credential but could not read it — the Keychain item is
    /// `WhenUnlockedThisDeviceOnly`, so a read on a locked device returns
    /// nothing. Deliberately distinct from `notAuthenticated`: conflating the
    /// two made a locked phone look like a revoked grant, and the app deleted
    /// its own token in response.
    case credentialUnavailable
    case requestFailed(status: Int, message: String)
    case malformedResponse(String)

    public var displayMessage: String {
        switch self {
        case .transportUnavailable(let detail):
            detail.isEmpty ? "Cannot reach GitHub" : detail
        case .notAuthenticated:
            "Not signed in to GitHub"
        case .credentialUnavailable:
            "Cannot read the saved sign-in — unlock the device"
        case .requestFailed(_, let message):
            message.isEmpty ? "GitHub rejected the request" : message
        case .malformedResponse:
            "Unexpected response from GitHub"
        }
    }

    /// Whether the right response is to show the sign-in flow again rather than
    /// an error. Kept here so both apps agree on it.
    public var requiresReauthentication: Bool {
        switch self {
        case .notAuthenticated: true
        case .requestFailed(let status, _): status == 401
        default: false
        }
    }
}
