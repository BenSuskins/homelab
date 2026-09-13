import Foundation

/// Read side of the credential, kept separate from the write side so that a
/// transport can be handed the ability to *use* a token without the ability to
/// replace or delete one.
public protocol TokenProviding: Sendable {
    func token() async -> String?
}

public protocol TokenStoring: TokenProviding {
    func save(_ token: String) async throws
    func clear() async throws
}

/// Non-persistent, for tests and previews.
public actor InMemoryTokenStore: TokenStoring {
    private var stored: String?

    public init(token: String? = nil) {
        self.stored = token
    }

    public func token() async -> String? { stored }
    public func save(_ token: String) async throws { stored = token }
    public func clear() async throws { stored = nil }
}
