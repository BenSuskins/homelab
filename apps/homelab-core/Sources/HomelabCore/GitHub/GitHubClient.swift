import Foundation

public struct GitHubClient: Sendable {
    private let transport: any GitHubTransport
    private let repository: RepositoryReference

    public init(transport: any GitHubTransport, repository: RepositoryReference = .homelab) {
        self.transport = transport
        self.repository = repository
    }

    // MARK: Reads

    public func latestRun(
        for workflow: DispatchableWorkflow
    ) async throws(GitHubFailure) -> WorkflowRunSummary? {
        let data = try await transport.send(.get(
            "repos/\(repository.slug)/actions/workflows/\(workflow.fileName)/runs"
                + "?per_page=1&branch=\(repository.defaultBranch)"
        ))

        let payload = try decode(WorkflowRunListPayload.self, from: data)
        guard let run = payload.workflowRuns.first else { return nil }

        let status = RunStatus(status: run.status, conclusion: run.conclusion)
        return WorkflowRunSummary(
            identifier: run.identifier,
            status: status,
            url: run.url,
            startedAt: run.startedAt,
            finishedAt: status.isOpen ? nil : run.updatedAt
        )
    }

    /// GraphQL rather than REST, and not for elegance: REST's `/pulls` list
    /// endpoint does not return `mergeable` at all — it exists only on the
    /// single-PR endpoint, computed lazily — so a REST port would quietly lose
    /// the field `canMerge` is built on and offer merge buttons that fail.
    /// GraphQL returns it as MERGEABLE/CONFLICTING/UNKNOWN, which is exactly
    /// what `MergeReadiness` already decodes, and both transports can issue it.
    public func openPullRequests() async throws(GitHubFailure) -> [PullRequestSummary] {
        let data = try await transport.send(.graphQL(
            Self.pullRequestQuery,
            variables: ["owner": repository.owner, "name": repository.name]
        ))

        let payload = try decode(PullRequestQueryPayload.self, from: data)
        return payload.data.repository.pullRequests.nodes.map { node in
            PullRequestSummary(
                number: node.number,
                title: node.title,
                authorLogin: node.author?.login ?? "ghost",
                isDraft: node.isDraft,
                readiness: MergeReadiness(mergeableField: node.mergeable),
                createdAt: node.createdAt,
                url: node.url
            )
        }
    }

    static let pullRequestQuery = """
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        pullRequests(states: OPEN, first: 50, orderBy: {field: CREATED_AT, direction: DESC}) {
          nodes {
            number
            title
            author { login }
            isDraft
            mergeable
            createdAt
            url
          }
        }
      }
    }
    """

    // MARK: Writes

    public func dispatch(_ workflow: DispatchableWorkflow) async throws(GitHubFailure) {
        _ = try await transport.send(.post(
            "repos/\(repository.slug)/actions/workflows/\(workflow.fileName)/dispatches",
            fields: ["ref": repository.defaultBranch]
        ))
    }

    public func cancelRun(identifier: Int) async throws(GitHubFailure) {
        _ = try await transport.send(.post(
            "repos/\(repository.slug)/actions/runs/\(identifier)/cancel"
        ))
    }

    /// Squash, always: one commit on `main` per pull request, which is one
    /// Update Homelab run, which is one line in the deploy log.
    public func squashMerge(pullRequestNumber: Int) async throws(GitHubFailure) {
        _ = try await transport.send(.put(
            "repos/\(repository.slug)/pulls/\(pullRequestNumber)/merge",
            fields: ["merge_method": "squash"]
        ))
    }

    // MARK: Plumbing

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws(GitHubFailure) -> Value {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw GitHubFailure.malformedResponse(String(describing: error))
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
