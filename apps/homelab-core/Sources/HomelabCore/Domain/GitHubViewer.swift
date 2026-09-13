import Foundation

/// The signed-in account, as far as this app cares: enough to put a face in the
/// corner and a name on the profile sheet.
///
/// It exists because the sign-out button moved off the actions screen. A
/// destructive control sitting under three buttons that deploy six hosts was
/// one mis-tap from an unwanted surprise; behind an avatar it is where every
/// other app keeps it, and the avatar earns its place by answering which
/// account the phone is acting as.
public struct GitHubViewer: Equatable, Sendable, Codable, Identifiable {
    public let login: String
    public let name: String?
    public let avatarURL: URL?
    public let profileURL: URL?

    public var id: String { login }

    public init(
        login: String,
        name: String? = nil,
        avatarURL: URL? = nil,
        profileURL: URL? = nil
    ) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.profileURL = profileURL
    }

    public var displayName: String { name ?? login }

    /// The letter in the circle while the avatar loads, or when there is no
    /// avatar to load.
    public var initial: String {
        String(displayName.first ?? "?").uppercased()
    }
}
