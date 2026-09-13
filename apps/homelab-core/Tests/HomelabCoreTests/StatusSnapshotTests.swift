import Foundation
import Testing
@testable import HomelabCore

private func run(
    identifier: Int = 1,
    _ status: RunStatus,
    startedAt: Date? = Date(timeIntervalSince1970: 0),
    finishedAt: Date? = nil
) -> WorkflowRunSummary {
    WorkflowRunSummary(
        identifier: identifier,
        status: status,
        url: URL(string: "https://github.com/x/y/actions/runs/\(identifier)")!,
        startedAt: startedAt,
        finishedAt: finishedAt
    )
}

@Suite("StatusSnapshot")
struct StatusSnapshotTests {
    @Test("always renders every dispatchable workflow, even one that never ran")
    func rendersEveryWorkflow() {
        let snapshot = StatusSnapshot.make(
            runs: [.update: run(.succeeded)],
            pullRequests: [],
            lastRefreshedAt: nil
        )

        #expect(snapshot.runRows.count == DispatchableWorkflow.allCases.count)
        #expect(snapshot.row(for: .clean)?.status == .never)
    }

    @Test("orders pull requests newest first")
    func ordersPullRequestsNewestFirst() {
        let snapshot = StatusSnapshot.make(
            runs: [:],
            pullRequests: [pullRequest(number: 12), pullRequest(number: 141)],
            lastRefreshedAt: nil
        )

        #expect(snapshot.pullRequests.map(\.number) == [141, 12])
    }

    @Test("a workflow with an open run cannot be triggered but can be cancelled")
    func openRunBlocksTrigger() {
        let running = RunRow(workflow: .update, run: run(.running))

        #expect(running.canTrigger == false)
        #expect(running.canCancel)
    }

    @Test("a run parked at the approval gate still owns the workflow")
    func awaitingApprovalBlocksTrigger() {
        let parked = RunRow(workflow: .terraform, run: run(.awaitingApproval))

        // Nothing is executing, but dispatching again would race the parked run.
        #expect(parked.canTrigger == false)
        #expect(parked.canCancel)
    }

    @Test("a settled workflow can be triggered and cannot be cancelled")
    func settledRunAllowsTrigger() {
        for status in [RunStatus.succeeded, .failed, .cancelled, .never] {
            let row = RunRow(workflow: .clean, run: status == .never ? nil : run(status))
            #expect(row.canTrigger, "\(status) should allow a trigger")
            #expect(row.canCancel == false, "\(status) should not offer a cancel")
        }
    }

    private func pullRequest(number: Int) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title \(number)",
            authorLogin: "BenSuskins",
            isDraft: false,
            readiness: .mergeable,
            createdAt: Date(timeIntervalSince1970: 0),
            url: URL(string: "https://github.com/x/y/pull/\(number)")!
        )
    }
}

@Suite("GlyphState")
struct GlyphStateTests {
    @Test("a failure outranks everything else")
    func failureWins() {
        #expect(GlyphState.worstOf([.succeeded, .running, .failed]) == .failed)
    }

    @Test("an active run outranks success")
    func runningBeatsSuccess() {
        #expect(GlyphState.worstOf([.succeeded, .queued, .succeeded]) == .running)
    }

    @Test("all quiet reads as ok")
    func quietIsOk() {
        #expect(GlyphState.worstOf([.succeeded, .never, .cancelled]) == .ok)
    }

    @Test("a run parked at the approval gate does not raise the glyph")
    func awaitingApprovalIsNotAnAlarm() {
        // A deliberate consequence of notifying on failure only: a parked plan
        // waits quietly rather than nagging.
        #expect(GlyphState.worstOf([.succeeded, .awaitingApproval]) == .ok)
    }
}

@Suite("PollingSchedule")
struct PollingScheduleTests {
    @Test("tightens the interval while GitHub is doing work")
    func fastWhileActive() {
        let snapshot = StatusSnapshot.make(
            runs: [.update: run(.running)],
            pullRequests: [],
            lastRefreshedAt: nil
        )

        #expect(PollingSchedule.interval(for: snapshot) == PollingSchedule.active)
    }

    @Test("relaxes the interval when nothing is running")
    func slowWhenIdle() {
        let snapshot = StatusSnapshot.make(
            runs: [.update: run(.succeeded)],
            pullRequests: [],
            lastRefreshedAt: nil
        )

        #expect(PollingSchedule.interval(for: snapshot) == PollingSchedule.idle)
    }

    @Test("a run awaiting approval does not warrant fast polling")
    func approvalGateDoesNotPoll() {
        // It will sit there until a human acts, so polling it every 10s is waste.
        let snapshot = StatusSnapshot.make(
            runs: [.terraform: run(.awaitingApproval)],
            pullRequests: [],
            lastRefreshedAt: nil
        )

        #expect(PollingSchedule.interval(for: snapshot) == PollingSchedule.idle)
    }
}

@Suite("FailureDetector")
struct FailureDetectorTests {
    private func snapshot(_ workflow: DispatchableWorkflow, _ summary: WorkflowRunSummary) -> StatusSnapshot {
        StatusSnapshot.make(runs: [workflow: summary], pullRequests: [], lastRefreshedAt: nil)
    }

    @Test("stays silent on first launch, however bad the news")
    func silentWithoutHistory() {
        let current = snapshot(.update, run(.failed))

        // Without a previous snapshot, last week's breakage would look new and
        // fire a notification every single launch.
        #expect(FailureDetector.newFailures(previous: nil, current: current).isEmpty)
    }

    @Test("reports a run that has just turned red")
    func reportsFreshFailure() {
        let previous = snapshot(.update, run(identifier: 1, .running))
        let current = snapshot(.update, run(identifier: 1, .failed))

        #expect(FailureDetector.newFailures(previous: previous, current: current).count == 1)
    }

    @Test("does not report the same failure twice")
    func doesNotRepeatItself() {
        let previous = snapshot(.update, run(identifier: 1, .failed))
        let current = snapshot(.update, run(identifier: 1, .failed))

        #expect(FailureDetector.newFailures(previous: previous, current: current).isEmpty)
    }

    @Test("reports a second failed run of the same workflow")
    func reportsRepeatFailureFromANewRun() {
        let previous = snapshot(.update, run(identifier: 1, .failed))
        let current = snapshot(.update, run(identifier: 2, .failed))

        // Same workflow, same colour, different run — you broke it again.
        #expect(FailureDetector.newFailures(previous: previous, current: current).count == 1)
    }

    @Test("says nothing when a run succeeds")
    func silentOnSuccess() {
        let previous = snapshot(.update, run(identifier: 1, .running))
        let current = snapshot(.update, run(identifier: 1, .succeeded))

        #expect(FailureDetector.newFailures(previous: previous, current: current).isEmpty)
    }
}

@Suite("Run durations and relative time")
struct RelativeTimeTests {
    @Test("an open run measures against now, not its stale updated_at")
    func openRunMeasuresAgainstNow() {
        let start = Date(timeIntervalSince1970: 1_000)
        let summary = run(.running, startedAt: start, finishedAt: nil)

        let elapsed = summary.duration(now: Date(timeIntervalSince1970: 1_190))

        #expect(elapsed == 190)
    }

    @Test("a finished run measures to its conclusion")
    func finishedRunMeasuresToConclusion() {
        let start = Date(timeIntervalSince1970: 1_000)
        let summary = run(.succeeded, startedAt: start, finishedAt: Date(timeIntervalSince1970: 1_241))

        let elapsed = summary.duration(now: Date(timeIntervalSince1970: 99_999))

        #expect(elapsed == 241)
    }

    @Test("formats durations with minutes and padded seconds")
    func formatsDuration() {
        #expect(RelativeTime.duration(241) == "4m 01s")
        #expect(RelativeTime.duration(45) == "45s")
    }

    @Test("formats ages coarsely")
    func formatsAge() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(RelativeTime.ago(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(RelativeTime.ago(now.addingTimeInterval(-600), now: now) == "10m ago")
        #expect(RelativeTime.ago(now.addingTimeInterval(-7_200), now: now) == "2h ago")
        #expect(RelativeTime.ago(now.addingTimeInterval(-259_200), now: now) == "3d ago")
    }
}
