import Foundation
import HomelabCore
import Testing
@testable import HomelabMenuBarCore

/// The fakes in `HomelabCore` assert that our code handles GitHub's output
/// correctly. These assert that GitHub still *produces* that output — the one
/// thing a fake can never tell us. Strictly read-only: no dispatch, no cancel,
/// no merge.
///
/// They need a real token. Since ADR-0004 was amended these run against the
/// same Keychain item the app signs into, so sign in once and they work; with
/// no token they skip rather than fail, because CI has no Keychain to sign
/// into and a red build there would say nothing about GitHub.
///
/// Run with: `swift test --filter Contract`
@Suite("Contract (real GitHub, read-only)", .tags(.contract))
struct ContractTests {
    private func client() async -> GitHubClient? {
        let tokens = KeychainTokenStore(
            service: HomelabConfiguration.macOS.keychainService
        )
        guard await tokens.token() != nil else { return nil }
        return GitHubClient(transport: URLSessionTransport(tokens: tokens), repository: .homelab)
    }

    @Test("the workflow runs endpoint still has the fields we decode")
    func workflowRunsShapeIsStable() async throws {
        guard let client = await client() else { return }

        let run = try await client.latestRun(for: .update)

        let found = try #require(run, "Update Homelab has never run on main")
        #expect(found.identifier > 0)
        #expect(found.url.absoluteString.contains("/actions/runs/"))
        #expect(found.startedAt != nil)
    }

    @Test("all three dispatchable workflows still exist in the repository")
    func everyWorkflowResolves() async throws {
        guard let client = await client() else { return }

        for workflow in DispatchableWorkflow.allCases {
            // A missing workflow file is a 404, which surfaces as a thrown
            // GitHubFailure rather than an empty list.
            _ = try await client.latestRun(for: workflow)
        }
    }

    /// The one that would have caught the REST/GraphQL trap: `mergeable` is not
    /// on REST's `/pulls` list endpoint at all, so this asserts both that the
    /// GraphQL query still parses server-side and that the field is still
    /// being returned.
    @Test("the GraphQL pull request query still returns the fields we decode")
    func pullRequestShapeIsStable() async throws {
        guard let client = await client() else { return }

        let pullRequests = try await client.openPullRequests()

        for pullRequest in pullRequests {
            #expect(pullRequest.number > 0)
            #expect(!pullRequest.title.isEmpty)
            #expect(pullRequest.url.absoluteString.contains("/pull/"))
            #expect(!pullRequest.authorLogin.isEmpty)
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
