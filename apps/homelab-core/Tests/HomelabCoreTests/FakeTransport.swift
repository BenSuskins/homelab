import Foundation
@testable import HomelabCore

/// Stands in for GitHub. It records what was asked and replies with canned
/// bytes, so every layer above it — decoding, mapping, snapshot building — runs
/// for real. Nothing is stubbed except the network boundary itself.
final class FakeTransport: GitHubTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(matches: @Sendable (GitHubRequest) -> Bool, result: Result<Data, GitHubFailure>)] = []
    private var recorded: [GitHubRequest] = []

    var requests: [GitHubRequest] {
        lock.withLock { recorded }
    }

    /// Every request flattened to a searchable string, so a test can assert on
    /// "this path was asked for" without rebuilding the whole value.
    var descriptions: [String] {
        requests.map(Self.describe)
    }

    static func describe(_ request: GitHubRequest) -> String {
        switch request.body {
        case .rest(let method, let path, let fields):
            let pairs = fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: "&")
            return "\(method.rawValue) \(path)\(pairs.isEmpty ? "" : " " + pairs)"
        case .graphQL(let query, let variables):
            let pairs = variables.keys.sorted().map { "\($0)=\(variables[$0]!)" }.joined(separator: "&")
            return "GRAPHQL \(query) \(pairs)"
        }
    }

    func stub(containing fragment: String, json: String) {
        stub(containing: fragment, with: Data(json.utf8))
    }

    func stub(containing fragment: String, with data: Data) {
        lock.withLock {
            responses.append((
                matches: { Self.describe($0).contains(fragment) },
                result: .success(data)
            ))
        }
    }

    func stub(containing fragment: String, failure: GitHubFailure) {
        lock.withLock {
            responses.append((
                matches: { Self.describe($0).contains(fragment) },
                result: .failure(failure)
            ))
        }
    }

    func send(_ request: GitHubRequest) async throws(GitHubFailure) -> Data {
        let result: Result<Data, GitHubFailure> = lock.withLock {
            recorded.append(request)
            let match = responses.first { $0.matches(request) }
            return match?.result ?? .success(Self.emptyResponse(for: request))
        }

        switch result {
        case .success(let data): return data
        case .failure(let failure): throw failure
        }
    }

    /// An unstubbed call answers "nothing there" rather than undecodable bytes,
    /// so a test that cares about one endpoint does not have to stub the others
    /// to keep the refresh from failing for an unrelated reason.
    private static func emptyResponse(for request: GitHubRequest) -> Data {
        switch request.body {
        case .graphQL: Data(Samples.noPullRequests.utf8)
        case .rest: Data(Samples.noWorkflowRuns.utf8)
        }
    }
}
