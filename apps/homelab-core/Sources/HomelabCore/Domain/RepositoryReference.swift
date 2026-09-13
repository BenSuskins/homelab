import Foundation

public struct RepositoryReference: Sendable, Equatable, Codable {
    public let owner: String
    public let name: String
    public let defaultBranch: String

    public init(owner: String, name: String, defaultBranch: String = "main") {
        self.owner = owner
        self.name = name
        self.defaultBranch = defaultBranch
    }

    public var slug: String { "\(owner)/\(name)" }

    public var browserURL: URL {
        URL(string: "https://github.com/\(slug)")!
    }

    public var actionsURL: URL {
        browserURL.appendingPathComponent("actions")
    }

    public static let homelab = RepositoryReference(
        owner: "BenSuskins",
        name: "homelab"
    )
}

/// The three destinations both apps link out to. Homepage stays the front door
/// for the ~25 proxied services, so this list deliberately does not mirror it.
public struct QuickLink: Sendable, Equatable, Identifiable {
    public let title: String
    public let symbolName: String
    public let url: URL

    public var id: String { url.absoluteString }

    public static func standard(for repository: RepositoryReference) -> [QuickLink] {
        [
            QuickLink(
                title: "Homepage",
                symbolName: "house",
                url: URL(string: "https://home.suskins.co.uk")!
            ),
            QuickLink(
                title: "Actions",
                symbolName: "play.rectangle",
                url: repository.actionsURL
            ),
            QuickLink(
                title: "Repo",
                symbolName: "chevron.left.forwardslash.chevron.right",
                url: repository.browserURL
            ),
        ]
    }
}
