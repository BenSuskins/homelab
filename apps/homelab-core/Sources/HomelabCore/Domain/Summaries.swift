import Foundation

public struct WorkflowRunSummary: Equatable, Sendable, Codable {
    public let identifier: Int
    public let status: RunStatus
    public let url: URL
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(
        identifier: Int,
        status: RunStatus,
        url: URL,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        self.identifier = identifier
        self.status = status
        self.url = url
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public func duration(now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        let end = status.isOpen ? now : (finishedAt ?? now)
        return max(0, end.timeIntervalSince(startedAt))
    }
}

public enum MergeReadiness: String, Equatable, Sendable, Codable {
    case mergeable
    case conflicting
    case unknown

    init(mergeableField value: String) {
        switch value.uppercased() {
        case "MERGEABLE": self = .mergeable
        case "CONFLICTING": self = .conflicting
        default: self = .unknown
        }
    }
}

public struct PullRequestSummary: Equatable, Sendable, Codable, Identifiable {
    public let number: Int
    public let title: String
    public let authorLogin: String
    public let isDraft: Bool
    public let readiness: MergeReadiness
    public let createdAt: Date
    public let url: URL

    public var id: Int { number }

    /// Merging pushes to `main`, which triggers Update Homelab — so the button
    /// is only offered when GitHub is certain the merge will succeed.
    public var canMerge: Bool {
        readiness == .mergeable && !isDraft
    }

    public init(
        number: Int,
        title: String,
        authorLogin: String,
        isDraft: Bool,
        readiness: MergeReadiness,
        createdAt: Date,
        url: URL
    ) {
        self.number = number
        self.title = title
        self.authorLogin = authorLogin
        self.isDraft = isDraft
        self.readiness = readiness
        self.createdAt = createdAt
        self.url = url
    }
}
