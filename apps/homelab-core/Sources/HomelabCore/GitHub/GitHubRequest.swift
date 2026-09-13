import Foundation

/// One call to GitHub, described without reference to how it will be made.
///
/// This is what replaced an argv array as the thing `GitHubClient` produces.
/// `gh api` and `URLSession` are both able to issue every shape here, which is
/// the whole point: the client stopped knowing which one is on the other side.
public struct GitHubRequest: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public enum Body: Sendable, Equatable {
        /// A REST path relative to the API root, with no leading slash —
        /// `repos/owner/name/actions/runs`. Fields become a JSON body on a
        /// write and are unused on a read, matching `gh api -f`.
        case rest(method: Method, path: String, fields: [String: String])
        /// Variables are all strings because that is the only type `gh api
        /// graphql -f` can express, and both transports must agree.
        case graphQL(query: String, variables: [String: String])
    }

    public let body: Body

    public init(body: Body) {
        self.body = body
    }

    public static func get(_ path: String) -> GitHubRequest {
        GitHubRequest(body: .rest(method: .get, path: path, fields: [:]))
    }

    public static func post(_ path: String, fields: [String: String] = [:]) -> GitHubRequest {
        GitHubRequest(body: .rest(method: .post, path: path, fields: fields))
    }

    public static func put(_ path: String, fields: [String: String] = [:]) -> GitHubRequest {
        GitHubRequest(body: .rest(method: .put, path: path, fields: fields))
    }

    public static func graphQL(
        _ query: String,
        variables: [String: String] = [:]
    ) -> GitHubRequest {
        GitHubRequest(body: .graphQL(query: query, variables: variables))
    }
}

/// The single seam between this package and GitHub. Faking it fakes the
/// network; on macOS the real one spawns `gh`, on iOS it is `URLSession`.
public protocol GitHubTransport: Sendable {
    func send(_ request: GitHubRequest) async throws(GitHubFailure) -> Data
}
