import Foundation

/// The values that differ between this build and a fork of it, in one place so
/// none of them is buried in a view — and shared, so the two apps cannot drift
/// onto different OAuth clients or Keychain items.
public struct HomelabConfiguration: Sendable {
    /// The OAuth app's client ID.
    ///
    /// Public by design. Device flow has no client secret — that is the reason
    /// it was chosen (ADR-0004) — so this is not a credential, and committing
    /// it is deliberate rather than an oversight.
    ///
    /// Registered at https://github.com/settings/developers as an **OAuth app**
    /// (not a GitHub App, which needs a private key and a server to exchange
    /// it) with "Enable Device Flow" ticked.
    public let gitHubClientID: String

    /// Shared between the iOS app and its widget. Nil on macOS, which is a
    /// single process and has no extension to share with.
    public let appGroup: String?

    public let keychainService: String

    /// Shared Keychain access group, so the iOS widget can read the token and
    /// refresh on its own. Nil is a working default: without it the widget
    /// renders from the App Group cache instead of fetching.
    public let keychainAccessGroup: String?

    public init(
        gitHubClientID: String,
        appGroup: String? = nil,
        keychainService: String,
        keychainAccessGroup: String? = nil
    ) {
        self.gitHubClientID = gitHubClientID
        self.appGroup = appGroup
        self.keychainService = keychainService
        self.keychainAccessGroup = keychainAccessGroup
    }

    /// A fork that strips the client ID gets a disabled sign-in button and a
    /// line saying why, rather than a 400 from GitHub.
    public var isConfigured: Bool {
        !gitHubClientID.isEmpty
            && !gitHubClientID.hasSuffix("REPLACE_WITH_YOUR_CLIENT_ID")
    }

    public static let iOS = HomelabConfiguration(
        gitHubClientID: "Ov23liYVFMJmWmwdKHCN",
        appGroup: "group.co.uk.suskins.Homelab",
        keychainService: "co.uk.suskins.Homelab"
    )

    /// The same OAuth client as iOS: one app registration, one place to revoke.
    /// A separate Keychain service because the two are different apps on
    /// different machines, and signing one out should not sign out the other.
    public static let macOS = HomelabConfiguration(
        gitHubClientID: "Ov23liYVFMJmWmwdKHCN",
        keychainService: "co.uk.suskins.HomelabMenuBar"
    )
}
