import Foundation

/// Why a GitHub call did not produce usable bytes. Deliberately transport
/// neutral: it survived `gh` being one of two transports, and then `gh` being
/// removed altogether, without a case changing.
public enum GitHubFailure: Error, Equatable, Sendable {
    /// The transport itself could not run — `gh` is not installed, or the
    /// device has no route to `api.github.com`.
    case transportUnavailable(String)
    /// There is no credential, or the one we have has expired or been revoked.
    case notAuthenticated
    case requestFailed(status: Int, message: String)
    case malformedResponse(String)

    public var displayMessage: String {
        switch self {
        case .transportUnavailable(let detail):
            detail.isEmpty ? "Cannot reach GitHub" : detail
        case .notAuthenticated:
            "Not signed in to GitHub"
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
