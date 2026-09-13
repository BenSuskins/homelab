import Foundation
import Security

public struct KeychainFailure: Error, Equatable, Sendable {
    public let status: OSStatus
    public let operation: String

    public var localizedDescription: String {
        "Keychain \(operation) failed (\(status))"
    }
}

/// The token lives here and nowhere else — never in `UserDefaults`, never in
/// the snapshot cache, never in a log line.
///
/// `WhenUnlockedThisDeviceOnly` is deliberate on both halves: the token is
/// unreadable while the phone is locked, so a widget refresh on a locked device
/// falls back to its cache rather than fetching, and `ThisDeviceOnly` keeps it
/// out of an iCloud Keychain backup that would put a deploy credential on every
/// device signed into the same account.
public struct KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String
    private let accessGroup: String?

    public init(
        service: String = "co.uk.suskins.Homelab",
        account: String = "github-oauth-token",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func token() async -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) async throws {
        let data = Data(token.utf8)

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainFailure(status: updateStatus, operation: "update")
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainFailure(status: addStatus, operation: "add")
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(status: status, operation: "delete")
        }
    }
}
