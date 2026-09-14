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
        try await recentRuns(for: workflow, limit: 1).first
    }

    /// The same endpoint as `latestRun`, asked for a page instead of a row.
    ///
    /// One request answers both questions — what is it doing now, and what has
    /// it been doing — so adding history to the app cost no extra calls against
    /// the rate limit, only a larger page. The default is deliberately modest:
    /// twenty runs is several weeks of Terraform and a few days of Update,
    /// which is as far back as anything on screen looks.
    public func recentRuns(
        for workflow: DispatchableWorkflow,
        limit: Int = 20
    ) async throws(GitHubFailure) -> [WorkflowRunSummary] {
        let data = try await transport.send(.get(
            "repos/\(repository.slug)/actions/workflows/\(workflow.fileName)/runs"
                + "?per_page=\(max(1, limit))&branch=\(repository.defaultBranch)"
        ))

        let payload = try decode(WorkflowRunListPayload.self, from: data)
        return payload.workflowRuns.map { run in
            let status = RunStatus(status: run.status, conclusion: run.conclusion)
            return WorkflowRunSummary(
                identifier: run.identifier,
                status: status,
                url: run.url,
                startedAt: run.startedAt,
                // GitHub keeps stamping `updated_at` on a run that has not
                // finished, so it is only an end time once there is a verdict.
                finishedAt: status.isOpen ? nil : run.updatedAt
            )
        }
    }

    /// Who the token belongs to. Read once at sign-in for the profile button —
    /// it is the only thing in the app that needs to know, and an avatar in the
    /// corner is the honest answer to "which account is this phone acting as".
    public func viewer() async throws(GitHubFailure) -> GitHubViewer {
        let data = try await transport.send(.get("user"))
        let payload = try decode(ViewerPayload.self, from: data)

        return GitHubViewer(
            login: payload.login,
            name: payload.name,
            avatarURL: payload.avatarURL,
            profileURL: payload.profileURL
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
