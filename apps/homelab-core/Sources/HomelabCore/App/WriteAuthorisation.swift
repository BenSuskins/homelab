import Foundation

/// Asked before every write — dispatch, cancel, merge — and before nothing
/// else. A credential that runs Ansible against six hosts and squash-merges to
/// `main` is a deploy button in a pocket; a status glance is not, and should
/// not cost a Face ID prompt.
///
/// A protocol rather than a direct `LAContext` call so the macOS app can opt
/// out (it is already behind a login) and so tests never touch real biometrics.
public protocol WriteAuthorising: Sendable {
    /// `reason` is shown verbatim in the system prompt, so it says what is
    /// about to happen rather than that authentication is required.
    func authorise(reason: String) async -> Bool
}

/// macOS, previews, and tests: the write proceeds.
public struct AlwaysAuthorised: WriteAuthorising {
    public init() {}
    public func authorise(reason: String) async -> Bool { true }
}
