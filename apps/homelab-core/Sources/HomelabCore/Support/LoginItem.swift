import Foundation

/// What the system thinks of this app as a login item. `requiresApproval` and
/// `unavailable` are both "off", but for reasons the user can act on, so the
/// UI says which rather than showing an unexplained dead switch.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but switched off by hand in System Settings → Login Items.
    case requiresApproval
    /// The platform cannot resolve the bundle — running the bare SwiftPM
    /// executable rather than `Homelab.app`, typically — or has no such concept
    /// at all, which is the case on iOS.
    case unavailable
}

public struct LoginItemFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public protocol LoginItemControlling: Sendable {
    func status() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemFailure>
    /// Only the system can clear `requiresApproval`, so the UI offers a way
    /// there rather than a switch that refuses to move.
    func openSystemSettings()
}

/// iOS has no login items; an app is launched by the person holding the phone.
/// Reporting `.unavailable` rather than `.disabled` keeps the reconcile logic
/// from trying to register something that cannot exist.
public struct UnsupportedLoginItemService: LoginItemControlling {
    public init() {}

    public func status() -> LoginItemStatus { .unavailable }

    public func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemFailure> {
        .failure(LoginItemFailure(message: "Not supported on this platform"))
    }

    public func openSystemSettings() {}
}

/// The user's stated intent, which is not the same thing as the system status:
/// `make bundle` ad-hoc signs, so a rebuilt app can arrive with its
/// registration dropped. Remembering what was asked for is what lets the app
/// put it back.
///
/// `@unchecked` only because `UserDefaults` predates `Sendable`; it is
/// documented as thread-safe.
public struct LaunchAtLoginPreference: @unchecked Sendable {
    private static let key = "launchAtLoginRequested"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isRequested: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func record(_ requested: Bool) {
        defaults.set(requested, forKey: Self.key)
    }
}
