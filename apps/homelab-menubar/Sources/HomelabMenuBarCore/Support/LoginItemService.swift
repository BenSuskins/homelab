import Foundation
import HomelabCore
import ServiceManagement

/// The macOS half of `LoginItemControlling`. The protocol, the status enum and
/// the stored preference all live in `HomelabCore`; only `SMAppService` — which
/// does not exist on iOS — is here.
public struct LoginItemService: LoginItemControlling {
    public init() {}

    public func status() -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        case .notRegistered: .disabled
        @unknown default: .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemFailure> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(status())
        } catch {
            return .failure(LoginItemFailure(message: error.localizedDescription))
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
