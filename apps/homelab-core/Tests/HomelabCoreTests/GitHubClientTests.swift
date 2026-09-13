import Foundation
import Testing
@testable import HomelabCore

@Suite("GitHubClient")
struct GitHubClientTests {
    private func client(_ transport: FakeTransport) -> GitHubClient {
        GitHubClient(transport: transport, repository: .homelab)
    }

    @Test("decodes a completed successful run")
    func decodesSuccessfulRun() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(status: "completed", conclusion: "success")
        )

        let run = try await client(transport).latestRun(for: .update)

        #expect(run?.status == .succeeded)
        #expect(run?.identifier == 1001)
        #expect(run?.finishedAt != nil)
    }

    @Test("maps GitHub's waiting status onto awaiting approval")
    func mapsWaitingStatus() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "terraform.yml",
            json: Samples.workflowRuns(status: "waiting", conclusion: nil)
        )

        let run = try await client(transport).latestRun(for: .terraform)

        #expect(run?.status == .awaitingApproval)
        // An unfinished run has no end, even though GitHub keeps stamping updated_at.
        #expect(run?.finishedAt == nil)
    }

    @Test(
        "maps every conclusion the API can return",
        arguments: [
            ("completed", "success", RunStatus.succeeded),
            ("completed", "failure", RunStatus.failed),
            ("completed", "timed_out", RunStatus.failed),
            ("completed", "startup_failure", RunStatus.failed),
            ("completed", "cancelled", RunStatus.cancelled),
            ("completed", "skipped", RunStatus.succeeded),
            ("in_progress", nil, RunStatus.running),
            ("queued", nil, RunStatus.queued),
            ("requested", nil, RunStatus.queued),
        ]
    )
    func mapsConclusions(status: String, conclusion: String?, expected: RunStatus) async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(status: status, conclusion: conclusion)
        )

        let run = try await client(transport).latestRun(for: .update)

        #expect(run?.status == expected)
    }

    @Test("a workflow that never ran yields no run")
    func handlesNeverRun() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "clean.yml", json: Samples.noWorkflowRuns)

        let run = try await client(transport).latestRun(for: .clean)

        #expect(run == nil)
    }

    @Test("asks only for the latest run on the default branch")
    func queriesLatestRunOnDefaultBranch() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(status: "completed", conclusion: "success")
        )

        _ = try await client(transport).latestRun(for: .update)

        let described = try #require(transport.descriptions.first)
        #expect(described.hasPrefix("GET "))
        #expect(described.contains("per_page=1"))
        #expect(described.contains("branch=main"))
    }

    @Test("reads pull requests over GraphQL, which is the only source of mergeable")
    func decodesPullRequests() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "GRAPHQL", json: Samples.pullRequests)

        let pullRequests = try await client(transport).openPullRequests()

        #expect(pullRequests.count == 2)
        #expect(pullRequests[0].number == 141)
        #expect(pullRequests[0].authorLogin == "app/renovate")
        #expect(pullRequests[0].readiness == .mergeable)
        #expect(pullRequests[0].canMerge)

        // A null author decodes rather than throwing, and a conflicting draft
        // must never offer a merge button.
        #expect(pullRequests[1].authorLogin == "ghost")
        #expect(pullRequests[1].readiness == .conflicting)
        #expect(pullRequests[1].canMerge == false)
    }

    @Test("passes the repository to GraphQL as variables, not as string interpolation")
    func parameterisesTheQuery() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "GRAPHQL", json: Samples.noPullRequests)

        _ = try await client(transport).openPullRequests()

        let request = try #require(transport.requests.first)
        guard case .graphQL(let query, let variables) = request.body else {
            Issue.record("Expected a GraphQL request")
            return
        }
        #expect(variables["owner"] == "BenSuskins")
        #expect(variables["name"] == "homelab")
        #expect(query.contains("$owner: String!"))
        // The repository must not be baked into the query text.
        #expect(query.contains("BenSuskins") == false)
    }

    @Test("an empty repository yields no pull requests rather than throwing")
    func handlesNoPullRequests() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "GRAPHQL", json: Samples.noPullRequests)

        #expect(try await client(transport).openPullRequests().isEmpty)
    }

    @Test("dispatches against the default branch")
    func dispatchesWorkflow() async throws {
        let transport = FakeTransport()

        try await client(transport).dispatch(.clean)

        let described = try #require(transport.descriptions.first)
        #expect(described.contains("POST"))
        #expect(described.contains("repos/BenSuskins/homelab/actions/workflows/clean.yml/dispatches"))
        #expect(described.contains("ref=main"))
    }

    @Test("cancels by run identifier")
    func cancelsRun() async throws {
        let transport = FakeTransport()

        try await client(transport).cancelRun(identifier: 4242)

        let described = try #require(transport.descriptions.first)
        #expect(described.contains("POST"))
        #expect(described.contains("repos/BenSuskins/homelab/actions/runs/4242/cancel"))
    }

    @Test("merges by squashing")
    func squashMerges() async throws {
        let transport = FakeTransport()

        try await client(transport).squashMerge(pullRequestNumber: 141)

        let described = try #require(transport.descriptions.first)
        #expect(described.contains("PUT"))
        #expect(described.contains("merge_method=squash"))
        #expect(described.contains("repos/BenSuskins/homelab/pulls/141/merge"))
    }

    @Test("passes a transport failure through untranslated")
    func propagatesTransportFailure() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "update.yml", failure: .notAuthenticated)

        await #expect(throws: GitHubFailure.notAuthenticated) {
            try await client(transport).latestRun(for: .update)
        }
    }

    @Test("surfaces unparseable output instead of crashing")
    func surfacesMalformedOutput() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "update.yml", json: "not json at all")

        await #expect(throws: GitHubFailure.self) {
            try await client(transport).latestRun(for: .update)
        }
    }
}

@Suite("GitHubFailure")
struct GitHubFailureTests {
    @Test("says nothing about gh, which is one transport of two")
    func staysTransportNeutral() {
        for failure: GitHubFailure in [
            .notAuthenticated,
            .requestFailed(status: 500, message: ""),
            .malformedResponse("x"),
            .transportUnavailable(""),
        ] {
            #expect(failure.displayMessage.contains("gh ") == false)
        }
    }

    @Test("knows which failures mean sign in again")
    func identifiesReauthentication() {
        #expect(GitHubFailure.notAuthenticated.requiresReauthentication)
        #expect(GitHubFailure.requestFailed(status: 401, message: "").requiresReauthentication)
        #expect(GitHubFailure.requestFailed(status: 404, message: "").requiresReauthentication == false)
        #expect(GitHubFailure.transportUnavailable("offline").requiresReauthentication == false)
    }
}
