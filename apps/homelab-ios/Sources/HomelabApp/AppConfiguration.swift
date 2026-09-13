import Foundation

/// The handful of values that differ between this app and a fork of it, kept in
/// one place so none of them is buried in a view.
enum AppConfiguration {
    /// The OAuth app's client ID. Public by design — device flow has no client
    /// secret, which is the reason it was chosen: there is nothing here that
    /// needs a server to hold it (ADR-0004).
    ///
    /// Register at https://github.com/settings/developers with "Enable Device
    /// Flow" ticked, then paste the ID here. There is no build-time secret and
    /// no CI step; the placeholder simply makes the sign-in screen say so.
    static let gitHubClientID = "Iv1.REPLACE_WITH_YOUR_CLIENT_ID"

    static var isConfigured: Bool {
        !gitHubClientID.hasSuffix("REPLACE_WITH_YOUR_CLIENT_ID")
    }

    /// Shared with the widget extension so both read one cached snapshot.
    static let appGroup = "group.co.uk.suskins.Homelab"

    /// Shared Keychain access group, so the widget can read the token and
    /// refresh on its own.
    ///
    /// `nil` is a working default, not a broken one: the two targets are
    /// separate app IDs, so without a shared group the widget cannot read the
    /// token, its fetch fails, and it renders from the App Group cache the app
    /// wrote when it was last foregrounded. That is a widget that is only as
    /// fresh as your last visit — acceptable, given ADR-0005 already says it is
    /// not an alerting mechanism, but worth improving.
    ///
    /// To improve it: add a `keychain-access-groups` entitlement of
    /// `$(AppIdentifierPrefix)co.uk.suskins.Homelab` to **both** targets, then
    /// set this to your literal team prefix plus that suffix, e.g.
    /// `"ABCDE12345.co.uk.suskins.Homelab"`. The same value must go in
    /// `WidgetSettings.keychainAccessGroup`.
    static let keychainAccessGroup: String? = nil

    static let keychainService = "co.uk.suskins.Homelab"
}
