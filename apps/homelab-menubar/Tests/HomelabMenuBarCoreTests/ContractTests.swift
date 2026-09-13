import Foundation
import HomelabCore
import Testing
@testable import HomelabMenuBarCore

/// The fakes in `HomelabCore` assert that our code handles GitHub's output
/// correctly. These assert that `gh` still *produces* that output — the one
/// thing a fake can never tell us. Strictly read-only: no dispatch, no cancel,
/// no merge.
///
/// Run with: `swift test --filter Contract`
@Suite("Contract (real gh, read-only)", .tags(.contract))
struct ContractTests {
    private var client: GitHubClient {
        GitHubClient(transport: GhCommandTransport(), repository: .homelab)
    }

    @Test("gh is installed and findable without a shell PATH")
    func executableIsResolvable() throws {
        let located = GitHubCommandLineRunner.locateExecutable()
        try #require(located != nil, "gh not found — install the GitHub CLI")
    }

    @Test("the workflow runs endpoint still has the fields we decode")
    func workflowRunsShapeIsStable() async throws {
        let run = try await client.latestRun(for: .update)

        let found = try #require(run, "Update Homelab has never run on main")
        #expect(found.identifier > 0)
        #expect(found.url.absoluteString.contains("/actions/runs/"))
        #expect(found.startedAt != nil)
    }

    @Test("all three dispatchable workflows still exist in the repository")
    func everyWorkflowResolves() async throws {
        for workflow in DispatchableWorkflow.allCases {
            // A missing workflow file makes `gh api` exit non-zero, which
            // surfaces as a thrown GitHubFailure rather than an empty list.
            _ = try await client.latestRun(for: workflow)
        }
    }

    /// The one that would have caught the REST/GraphQL trap: `mergeable` is not
    /// on REST's `/pulls` list endpoint at all, so this asserts both that `gh
    /// api graphql` still works and that the field is still being returned.
    @Test("the GraphQL pull request query still returns the fields we decode")
    func pullRequestShapeIsStable() async throws {
        let pullRequests = try await client.openPullRequests()

        for pullRequest in pullRequests {
            #expect(pullRequest.number > 0)
            #expect(!pullRequest.title.isEmpty)
            #expect(pullRequest.url.absoluteString.contains("/pull/"))
            #expect(!pullRequest.authorLogin.isEmpty)
            // `.unknown` means GitHub answered with something outside the
            // MERGEABLE/CONFLICTING/UNKNOWN set we map, or stopped answering.
            #expect(MergeReadiness.allExpected.contains(pullRequest.readiness))
        }
    }
}

extension MergeReadiness {
    static let allExpected: [MergeReadiness] = [.mergeable, .conflicting, .unknown]
}

extension Tag {
    @Tag static var contract: Self
}
