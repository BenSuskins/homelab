import Foundation
import Testing
@testable import HomelabCore

final class RecordingNotifier: FailureNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var notified: [RunRow] = []

    var notifiedWorkflows: [DispatchableWorkflow] {
        lock.withLock { notified.map(\.workflow) }
    }

    func requestAuthorization() async {}

    func notify(_ row: RunRow) async {
        lock.withLock { notified.append(row) }
    }
}

/// Stands in for Face ID. Records what reason the user would have been shown,
/// because a prompt that says "Authenticate" tells them nothing about what is
/// about to happen to six hosts.
final class StubWriteAuthorisation: WriteAuthorising, @unchecked Sendable {
    private let lock = NSLock()
    private let allow: Bool
    private var reasons: [String] = []

    init(allow: Bool) {
        self.allow = allow
    }

    var requestedReasons: [String] {
        lock.withLock { reasons }
    }

    func authorise(reason: String) async -> Bool {
        lock.withLock { reasons.append(reason) }
        return allow
    }
}

@MainActor
@Suite("AppState")
struct AppStateTests {
    private func makeState(
        _ transport: FakeTransport,
        notifier: RecordingNotifier = RecordingNotifier(),
        authorisation: any WriteAuthorising = AlwaysAuthorised()
    ) -> AppState {
        AppState(
            client: GitHubClient(transport: transport, repository: .homelab),
            repository: .homelab,
            cache: SnapshotCache(fileURL: temporaryCacheURL()),
            notifier: notifier,
            writeAuthorisation: authorisation
        )
    }

    private func temporaryCacheURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("homelab-core-tests-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
    }

    private func stubHealthyRepository(_ transport: FakeTransport) {
        for workflow in DispatchableWorkflow.allCases {
            transport.stub(
                containing: workflow.fileName,
                json: Samples.workflowRuns(status: "completed", conclusion: "success")
            )
        }
        transport.stub(containing: "GRAPHQL", json: Samples.pullRequests)
    }

    @Test("shows a full set of rows before the first refresh lands")
    func startsFromPlaceholder() {
        let state = makeState(FakeTransport())

        #expect(state.snapshot.runRows.count == DispatchableWorkflow.allCases.count)
        #expect(state.snapshot.glyph == .ok)
    }

    @Test("populates every row and the pull request list on refresh")
    func refreshPopulatesSnapshot() async {
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport)

        await state.refresh()

        #expect(state.snapshot.row(for: .update)?.status == .succeeded)
        #expect(state.snapshot.pullRequests.count == 2)
        #expect(state.snapshot.lastRefreshedAt != nil)
        #expect(state.snapshot.errorMessage == nil)
    }

    @Test("keeps the last good data on screen when a refresh fails")
    func failedRefreshKeepsLastGoodData() async {
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport)
        await state.refresh()

        let failing = FakeTransport()
        failing.stub(containing: "update.yml", failure: .requestFailed(status: 500, message: "boom"))
        let degraded = makeState(failing)
        degraded.adopt(state.snapshot)

        await degraded.refresh()

        // The error is reported, but the rows survive rather than blanking.
        #expect(degraded.snapshot.errorMessage != nil)
        #expect(degraded.snapshot.row(for: .update)?.status == .succeeded)
    }

    @Test("keeps the failure as a value, so callers branch on a case not a string")
    func recordsFailureAsAValue() async {
        let transport = FakeTransport()
        transport.stub(containing: "update.yml", failure: .requestFailed(status: 401, message: "Bad credentials"))
        let state = makeState(transport)

        await state.refresh()

        // A revoked grant must be distinguishable from any other error without
        // matching on display text that someone might reword.
        #expect(state.lastFailure?.requiresReauthentication == true)
        #expect(state.snapshot.errorMessage == "Bad credentials")
    }

    @Test("clears the last failure once a refresh succeeds")
    func clearsFailureOnRecovery() async {
        let transport = FakeTransport()
        transport.stub(containing: "update.yml", failure: .transportUnavailable("offline"))
        let state = makeState(transport)
        await state.refresh()
        #expect(state.lastFailure != nil)

        let healthy = FakeTransport()
        stubHealthyRepository(healthy)
        let recovered = makeState(healthy)
        recovered.adopt(state.snapshot)
        await recovered.refresh()

        #expect(recovered.lastFailure == nil)
        #expect(recovered.snapshot.errorMessage == nil)
    }

    @Test("refuses to trigger a workflow that already has an open run")
    func refusesToTriggerAnOpenWorkflow() async {
        let transport = FakeTransport()
        transport.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(status: "in_progress", conclusion: nil)
        )
        let state = makeState(transport)
        await state.refresh()
        let readCount = transport.requests.count

        await state.trigger(.update)

        // No dispatch was attempted at all — this is the guard that replaces a
        // confirmation dialog.
        #expect(state.canTrigger(.update) == false)
        #expect(transport.requests.count == readCount)
    }

    @Test("dispatches a workflow whose last run has settled")
    func dispatchesSettledWorkflow() async {
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport)
        await state.refresh()

        await state.trigger(.clean)

        #expect(transport.descriptions.contains {
            $0.contains("POST") && $0.contains("clean.yml/dispatches")
        })
    }

    @Test("notifies once when a workflow turns red")
    func notifiesOnNewFailure() async {
        let notifier = RecordingNotifier()
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport, notifier: notifier)
        await state.refresh()

        let failing = FakeTransport()
        failing.stub(
            containing: "update.yml",
            json: Samples.workflowRuns(identifier: 2002, status: "completed", conclusion: "failure")
        )
        let second = makeState(failing, notifier: notifier)
        second.adopt(state.snapshot)
        await second.refresh()

        // Notifications are dispatched to a child task; give them a turn.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(second.snapshot.glyph == .failed)
        #expect(notifier.notifiedWorkflows == [.update])
    }

    @Test("will not merge a draft or a conflicting pull request")
    func refusesUnmergeablePullRequests() async {
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport)
        await state.refresh()

        let draft = try! #require(state.snapshot.pullRequests.first { $0.number == 139 })
        let readCount = transport.requests.count

        await state.merge(draft)

        #expect(transport.requests.count == readCount)
    }

    @Test("squash merges a ready pull request")
    func mergesReadyPullRequest() async {
        let transport = FakeTransport()
        stubHealthyRepository(transport)
        let state = makeState(transport)
        await state.refresh()

        let ready = try! #require(state.snapshot.pullRequests.first { $0.number == 141 })
        await state.merge(ready)

        #expect(transport.descriptions.contains { $0.contains("merge_method=squash") })
    }
}

@MainActor
@Suite("Write authorisation")
struct WriteAuthorisationTests {
    private func makeState(
        _ transport: FakeTransport,
        _ authorisation: any WriteAuthorising
    ) -> AppState {
        AppState(
            client: GitHubClient(transport: transport, repository: .homelab),
            cache: SnapshotCache(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("auth-\(UUID().uuidString)")
                    .appendingPathComponent("snapshot.json")
            ),
            writeAuthorisation: authorisation
        )
    }

    private func stubSettled(_ transport: FakeTransport) {
        for workflow in DispatchableWorkflow.allCases {
            transport.stub(
                containing: workflow.fileName,
                json: Samples.workflowRuns(status: "completed", conclusion: "success")
            )
        }
        transport.stub(containing: "GRAPHQL", json: Samples.pullRequests)
    }

    @Test("a refused prompt writes nothing at all")
    func refusalBlocksTheWrite() async {
        let transport = FakeTransport()
        stubSettled(transport)
        let authorisation = StubWriteAuthorisation(allow: false)
        let state = makeState(transport, authorisation)
        await state.refresh()
        let readCount = transport.requests.count

        await state.trigger(.clean)

        #expect(transport.requests.count == readCount)
        #expect(authorisation.requestedReasons.count == 1)
    }

    @Test("the prompt says what is about to happen, not that auth is needed")
    func promptNamesTheConsequence() async {
        let transport = FakeTransport()
        stubSettled(transport)
        let authorisation = StubWriteAuthorisation(allow: true)
        let state = makeState(transport, authorisation)
        await state.refresh()

        await state.trigger(.update)
        let ready = try! #require(state.snapshot.pullRequests.first { $0.number == 141 })
        await state.merge(ready)

        #expect(authorisation.requestedReasons.first == "Run Update Homelab")
        #expect(authorisation.requestedReasons.last?.contains("this deploys") == true)
    }

    @Test("reads are never gated — a status glance costs no prompt")
    func readsAreUngated() async {
        let transport = FakeTransport()
        stubSettled(transport)
        let authorisation = StubWriteAuthorisation(allow: true)
        let state = makeState(transport, authorisation)

        await state.refresh()

        #expect(authorisation.requestedReasons.isEmpty)
    }
}

@Suite("SnapshotCache")
struct SnapshotCacheTests {
    @Test("round-trips a snapshot so a surface paints instantly at launch")
    func roundTripsSnapshot() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cache-test-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
        let cache = SnapshotCache(fileURL: url)

        let original = StatusSnapshot.make(
            runs: [.update: WorkflowRunSummary(
                identifier: 7,
                status: .failed,
                url: URL(string: "https://github.com/x/y/actions/runs/7")!,
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 70)
            )],
            pullRequests: [],
            lastRefreshedAt: Date(timeIntervalSince1970: 100)
        )

        cache.save(original)

        #expect(cache.load() == original)
    }

    @Test("returns nothing rather than throwing when no cache exists")
    func missingCacheIsNotAnError() {
        let cache = SnapshotCache(
            fileURL: URL(fileURLWithPath: "/nonexistent/homelab/snapshot.json")
        )

        #expect(cache.load() == nil)
    }
}
