import Foundation
@testable import HomelabCore

/// Stands in for `SMAppService`. It records what was asked of it and reports a
/// status the test controls, so the reconciliation logic runs for real without
/// touching the user's real login items.
final class FakeLoginItemService: LoginItemControlling, @unchecked Sendable {
    enum Write: Equatable {
        case register
        case unregister
        case openSystemSettings
    }

    private let lock = NSLock()
    private var currentStatus: LoginItemStatus
    private var registrationFailure: LoginItemFailure?
    private var recorded: [Write] = []

    init(status: LoginItemStatus = .disabled, registrationFailure: LoginItemFailure? = nil) {
        self.currentStatus = status
        self.registrationFailure = registrationFailure
    }

    var writes: [Write] {
        lock.withLock { recorded }
    }

    func status() -> LoginItemStatus {
        lock.withLock { currentStatus }
    }

    func openSystemSettings() {
        lock.withLock { recorded.append(.openSystemSettings) }
    }

    func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemFailure> {
        lock.withLock {
            recorded.append(enabled ? .register : .unregister)

            if let registrationFailure {
                return .failure(registrationFailure)
            }
            currentStatus = enabled ? .enabled : .disabled
            return .success(currentStatus)
        }
    }
}

extension LaunchAtLoginPreference {
    /// A preference backed by a throwaway suite, so tests never touch the real
    /// user defaults.
    static func temporary() -> LaunchAtLoginPreference {
        LaunchAtLoginPreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }
}
