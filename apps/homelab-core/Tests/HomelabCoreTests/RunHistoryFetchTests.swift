import Foundation
import Testing
@testable import HomelabCore

@Suite("Fetching run history")
struct RunHistoryFetchTests {
    private func client(_ transport: FakeTransport) -> GitHubClient {
        GitHubClient(transport: transport, repository: .homelab)
    }

    @Test("asks for a page of runs on the default branch")
    func asksForAPage() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRunPage([
                (status: "completed", conclusion: "success", minutes: 4),
                (status: "completed", conclusion: "failure", minutes: 2),
            ])
        )

        let runs = try await client(transport).recentRuns(for: .update, limit: 20)

        let described = try #require(transport.descriptions.first)
        #expect(described.contains("per_page=20"))
        #expect(described.contains("branch=main"))
        #expect(runs.count == 2)
        #expect(runs.map(\.status) == [.succeeded, .failed])
    }

    @Test("the latest run is the first of the same page")
    func latestRunAsksForOne() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(status: "completed", conclusion: "success")
        )

        let run = try await client(transport).latestRun(for: .update)

        // One request, one row: history did not make the cheap question dearer.
        #expect(transport.requests.count == 1)
        #expect(try #require(transport.descriptions.first).contains("per_page=1"))
        #expect(run?.identifier == 1001)
    }

    @Test("an open run in the page has no end time")
    func openRunHasNoEnd() async throws {
        let transport = FakeTransport()
        transport.stub(
            containing: "clean.yml",
            json: Samples.workflowRunPage([
                (status: "in_progress", conclusion: nil, minutes: 0),
                (status: "completed", conclusion: "success", minutes: 3),
            ])
        )

        let runs = try await client(transport).recentRuns(for: .clean)

        #expect(runs[0].status == .running)
        // GitHub keeps stamping updated_at on a run that has not finished.
        #expect(runs[0].finishedAt == nil)
        #expect(runs[1].finishedAt != nil)
    }

    @Test("reads the signed-in account for the profile button")
    func readsViewer() async throws {
        let transport = FakeTransport()
        transport.stub(containing: "GET user", json: Samples.viewer)

        let viewer = try await client(transport).viewer()

        #expect(viewer.login == "BenSuskins")
        #expect(viewer.displayName == "Ben Suskins")
        #expect(viewer.initial == "B")
        #expect(viewer.avatarURL != nil)
    }

    @Test("an account with no display name falls back to the login")
    func viewerWithoutName() {
        let viewer = GitHubViewer(login: "renovate")

        #expect(viewer.displayName == "renovate")
        #expect(viewer.initial == "R")
    }
}

@MainActor
@Suite("AppState history")
struct AppStateHistoryTests {
    private func makeState(_ transport: FakeTransport) -> AppState {
        AppState(
            client: GitHubClient(transport: transport, repository: .homelab),
            repository: .homelab,
            cache: SnapshotCache(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("\(UUID().uuidString).json")
            )
        )
    }

    private func stubRepository(_ transport: FakeTransport) {
        for workflow in DispatchableWorkflow.allCases {
            transport.stub(
                containing: workflow.fileName,
                json: Samples.workflowRunPage([
                    (status: "completed", conclusion: "success", minutes: 4),
                    (status: "completed", conclusion: "failure", minutes: 9),
                    (status: "completed", conclusion: "success", minutes: 5),
                ])
            )
        }
        transport.stub(containing: "GRAPHQL", json: Samples.pullRequests)
    }

    @Test("a refresh fills in both the present and the past")
    func refreshBuildsHistory() async {
        let transport = FakeTransport()
        stubRepository(transport)
        let state = makeState(transport)

        await state.refresh()

        #expect(state.snapshot.runRows.count == DispatchableWorkflow.allCases.count)
        #expect(state.history.histories.count == DispatchableWorkflow.allCases.count)
        #expect(state.runHistory(for: .update)?.runs.count == 3)
        // The row and the history agree about the newest run, because they were
        // built from the same response.
        #expect(state.snapshot.row(for: .update)?.run?.identifier
            == state.runHistory(for: .update)?.latest?.identifier)
        #expect(state.history.successRate == 2.0 / 3.0)
    }

    @Test("a poll while a run is active does not re-fetch twenty runs")
    func pollsShallowly() async {
        let transport = FakeTransport()
        stubRepository(transport)
        let state = makeState(transport)

        await state.refresh()
        let afterFirst = transport.descriptions.filter { $0.contains("per_page=20") }.count
        await state.refresh()
        let afterSecond = transport.descriptions.filter { $0.contains("per_page=20") }.count

        #expect(afterFirst == DispatchableWorkflow.allCases.count)
        // The second pass asks for one run each: twenty of them do not change
        // every ten seconds, and the phone is on someone's mobile data.
        #expect(afterSecond == afterFirst)
        #expect(transport.descriptions.contains { $0.contains("per_page=1") })
        // The history it already had survives the shallow pass.
        #expect(state.runHistory(for: .update)?.runs.count == 3)
    }

    @Test("a write forces the next refresh to go deep")
    func invalidationForcesDeepFetch() async {
        let transport = FakeTransport()
        stubRepository(transport)
        let state = makeState(transport)

        await state.refresh()
        state.invalidateHistory()
        await state.refresh()

        let deep = transport.descriptions.filter { $0.contains("per_page=20") }.count
        #expect(deep == DispatchableWorkflow.allCases.count * 2)
    }

    @Test("staleness is measured, not guessed")
    func historyStaleness() {
        let now = Date()

        #expect(AppState.isHistoryStale(nil, now: now))
        #expect(AppState.isHistoryStale(now.addingTimeInterval(-10), now: now) == false)
        #expect(AppState.isHistoryStale(now.addingTimeInterval(-300), now: now))
    }
}
