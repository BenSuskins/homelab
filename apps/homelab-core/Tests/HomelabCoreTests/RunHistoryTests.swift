import Foundation
import Testing
@testable import HomelabCore

@Suite("Run history")
struct RunHistoryTests {
    private func run(
        _ identifier: Int,
        _ status: RunStatus,
        minutes: Double,
        startedAt: Date = Date(timeIntervalSince1970: 1_757_779_200)
    ) -> WorkflowRunSummary {
        WorkflowRunSummary(
            identifier: identifier,
            status: status,
            url: URL(string: "https://github.com/BenSuskins/homelab/actions/runs/\(identifier)")!,
            startedAt: startedAt,
            finishedAt: status.isOpen ? nil : startedAt.addingTimeInterval(minutes * 60)
        )
    }

    @Test("judges only the runs that reached a verdict")
    func judgesCompletedRuns() {
        let history = RunHistory(workflow: .update, runs: [
            run(5, .running, minutes: 1),
            run(4, .succeeded, minutes: 4),
            run(3, .failed, minutes: 2),
            run(2, .cancelled, minutes: 1),
            run(1, .succeeded, minutes: 3),
        ])

        // Running is not a verdict, and a run somebody stopped is not evidence
        // about the workflow either way — so neither moves the pass rate.
        #expect(history.judged.count == 3)
        #expect(history.successCount == 2)
        #expect(history.failureCount == 1)
        #expect(history.successRate == 2.0 / 3.0)
    }

    @Test("no history is not a perfect record")
    func emptyHistoryHasNoRate() {
        // Nil rather than 1.0, so "never run" and "never failed" stay
        // distinguishable on a screen that colours one of them green.
        #expect(RunHistory(workflow: .clean, runs: []).successRate == nil)
        #expect(RunHistory(workflow: .clean, runs: []).medianDuration == nil)
    }

    @Test("takes the median duration, so one bad run does not move it")
    func takesMedianDuration() {
        let history = RunHistory(workflow: .update, runs: [
            run(3, .succeeded, minutes: 4),
            run(2, .succeeded, minutes: 20),
            run(1, .succeeded, minutes: 5),
        ])

        #expect(history.medianDuration == 5 * 60)
        #expect(history.longestDuration == 20 * 60)
    }

    @Test("averages the middle pair when the count is even")
    func medianOfEvenCount() {
        let history = RunHistory(workflow: .update, runs: [
            run(4, .succeeded, minutes: 2),
            run(3, .succeeded, minutes: 4),
            run(2, .succeeded, minutes: 6),
            run(1, .succeeded, minutes: 8),
        ])

        #expect(history.medianDuration == 5 * 60)
    }

    @Test("charts oldest first, which is the direction a chart reads")
    func barsAreChronological() {
        let history = RunHistory(workflow: .update, runs: [
            run(3, .failed, minutes: 2),
            run(2, .succeeded, minutes: 3),
            run(1, .succeeded, minutes: 4),
        ])

        #expect(history.bars.map(\.identifier) == [1, 2, 3])
        #expect(history.bars.map(\.index) == [0, 1, 2])
        #expect(history.bars.last?.status == .failed)
        // An open run has no duration and would draw as a bar of zero.
        #expect(history.bars.allSatisfy { $0.duration > 0 })
    }

    @Test("an open run is excluded from the bars entirely")
    func openRunsAreNotBars() {
        let history = RunHistory(workflow: .update, runs: [
            run(2, .running, minutes: 0),
            run(1, .succeeded, minutes: 3),
        ])

        #expect(history.bars.count == 1)
        #expect(history.latest?.status == .running)
    }

    @Test("reports the last success and the last failure separately")
    func reportsLastOutcomes() {
        let older = Date(timeIntervalSince1970: 1_757_600_000)
        let newer = Date(timeIntervalSince1970: 1_757_779_200)

        let history = RunHistory(workflow: .update, runs: [
            run(2, .failed, minutes: 1, startedAt: newer),
            run(1, .succeeded, minutes: 1, startedAt: older),
        ])

        #expect(history.lastFailureAt == newer.addingTimeInterval(60))
        #expect(history.lastSuccessAt == older.addingTimeInterval(60))
    }

    @Test("counts runs inside a window for the cadence line")
    func countsRecentRuns() {
        let now = Date()
        let history = RunHistory(workflow: .update, runs: [
            run(3, .succeeded, minutes: 1, startedAt: now.addingTimeInterval(-3_600)),
            run(2, .succeeded, minutes: 1, startedAt: now.addingTimeInterval(-86_400)),
            run(1, .succeeded, minutes: 1, startedAt: now.addingTimeInterval(-30 * 86_400)),
        ])

        #expect(history.runsSince(now.addingTimeInterval(-7 * 86_400)) == 2)
    }

    @Test("says nothing about a trend it cannot see")
    func trendNeedsEnoughRuns() {
        let history = RunHistory(workflow: .update, runs: [
            run(2, .succeeded, minutes: 4),
            run(1, .succeeded, minutes: 2),
        ])

        #expect(history.durationTrend == nil)
    }

    @Test("compares the recent half against the older half")
    func computesDurationTrend() {
        // Newest first: the two recent runs average 6 minutes, the two older
        // ones average 3, so the workflow has doubled in length.
        let history = RunHistory(workflow: .update, runs: [
            run(4, .succeeded, minutes: 6),
            run(3, .succeeded, minutes: 6),
            run(2, .succeeded, minutes: 3),
            run(1, .succeeded, minutes: 3),
        ])

        let trend = try? #require(history.durationTrend)
        #expect(trend == 1.0)
    }
}

@Suite("Activity history")
struct ActivityHistoryTests {
    private func run(_ identifier: Int, _ status: RunStatus, ago: TimeInterval) -> WorkflowRunSummary {
        let started = Date().addingTimeInterval(-ago)
        return WorkflowRunSummary(
            identifier: identifier,
            status: status,
            url: URL(string: "https://example.invalid/\(identifier)")!,
            startedAt: started,
            finishedAt: started.addingTimeInterval(120)
        )
    }

    @Test("pools every workflow's verdicts into one rate")
    func poolsSuccessRate() {
        let history = ActivityHistory(histories: [
            RunHistory(workflow: .update, runs: [
                run(1, .succeeded, ago: 3_600),
                run(2, .failed, ago: 7_200),
            ]),
            RunHistory(workflow: .clean, runs: [run(3, .succeeded, ago: 10_000)]),
        ])

        #expect(history.successRate == 2.0 / 3.0)
    }

    @Test("counts deploys as Update runs, because that is what deploys")
    func countsDeploys() {
        let week = Date().addingTimeInterval(-7 * 86_400)
        let history = ActivityHistory(histories: [
            RunHistory(workflow: .update, runs: [
                run(1, .succeeded, ago: 3_600),
                run(2, .succeeded, ago: 86_400),
                run(3, .succeeded, ago: 30 * 86_400),
            ]),
            RunHistory(workflow: .terraform, runs: [run(4, .succeeded, ago: 3_600)]),
        ])

        #expect(history.deployCount(since: week) == 2)
        #expect(history.runCount(since: week) == 3)
    }

    @Test("interleaves workflows into one timeline, newest first")
    func buildsTimeline() {
        let history = ActivityHistory(histories: [
            RunHistory(workflow: .update, runs: [run(1, .succeeded, ago: 60)]),
            RunHistory(workflow: .terraform, runs: [run(2, .failed, ago: 30)]),
            RunHistory(workflow: .clean, runs: [run(3, .succeeded, ago: 900)]),
        ])

        #expect(history.timeline.map(\.run.identifier) == [2, 1, 3])
        #expect(history.timeline.first?.workflow == .terraform)
    }
}
