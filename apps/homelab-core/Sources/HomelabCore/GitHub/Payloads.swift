import Foundation

/// Wire shapes, decoded and immediately mapped onto domain types so that
/// `html_url` and GraphQL's nesting never leak upward.
struct WorkflowRunListPayload: Decodable {
    let workflowRuns: [WorkflowRunPayload]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRunPayload: Decodable {
    let identifier: Int
    let status: String
    let conclusion: String?
    let url: URL
    let startedAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case status
        case conclusion
        case url = "html_url"
        case startedAt = "run_started_at"
        case updatedAt = "updated_at"
    }
}

/// GraphQL wraps everything in `data`, and `gh api graphql` passes that wrapper
/// through unchanged, so both transports decode the same three levels.
struct PullRequestQueryPayload: Decodable {
    struct Container: Decodable {
        let repository: Repository
    }

    struct Repository: Decodable {
        let pullRequests: Connection
    }

    struct Connection: Decodable {
        let nodes: [PullRequestNode]
    }

    let data: Container
}

struct PullRequestNode: Decodable {
    struct Author: Decodable {
        let login: String
    }

    let number: Int
    let title: String
    let author: Author?
    let isDraft: Bool
    let mergeable: String
    let createdAt: Date
    let url: URL
}

struct ViewerPayload: Decodable {
    let login: String
    let name: String?
    let avatarURL: URL?
    let profileURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarURL = "avatar_url"
        case profileURL = "html_url"
    }
}
