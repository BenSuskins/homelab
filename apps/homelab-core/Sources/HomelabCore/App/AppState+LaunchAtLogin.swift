import Foundation

extension AppState {
    public var launchesAtLogin: Bool {
        loginItemStatus == .enabled
    }

    /// Says why the switch is where it is, whenever that is not self-evident.
    public var launchAtLoginHint: String? {
        if let launchAtLoginError { return launchAtLoginError }

        return switch loginItemStatus {
        case .requiresApproval:
            "Switched off in System Settings — only you can switch it back on there."
        case .enabled, .disabled, .unavailable:
            nil
        }
    }

    public func openLoginItemSettings() {
        loginItem.openSystemSettings()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        switch loginItem.setEnabled(enabled) {
        case .success(let status):
            loginItemStatus = status
            launchAtLoginError = nil
            launchAtLoginPreference.record(enabled)
        case .failure(let failure):
            loginItemStatus = loginItem.status()
            launchAtLoginError = failure.message
        }
    }

    /// Run at every launch. The registration is keyed off the app's code
    /// signature and `make bundle` ad-hoc signs, so a reinstall can leave the
    /// login item quietly gone; re-assert it rather than just stopping.
    func reconcileLaunchAtLogin() {
        let status = loginItem.status()
        loginItemStatus = status

        switch status {
        case .enabled:
            // Registered outside the app, or surviving from a previous install.
            // Either way it is on, so record the intent and keep it on.
            launchAtLoginPreference.record(true)
        case .requiresApproval:
            // An approval only the user can give. Not ours to force.
            break
        case .disabled, .unavailable:
            // `.unavailable` is `SMAppService`'s `.notFound`, which it also
            // reports in cases where registering succeeds anyway — so the
            // attempt decides, never the status.
            if launchAtLoginPreference.isRequested {
                setLaunchAtLogin(true)
            }
        }
    }
}
