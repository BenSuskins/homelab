import Foundation

/// The last several runs of one workflow, and the handful of things worth
/// saying about them. A pure value computed from what GitHub returned, so the
/// bars, the pass rate and the cadence line are all testable without a view.
///
/// The app was a snapshot of now for its whole first version. This is the type
/// that gives it a past: the same fetch that answers "what is Update doing?"
/// also answers "how often does it fail, and is it getting slower?".
public struct RunHistory: Equatable, Sendable, Codable, Identifiable {
    public let workflow: DispatchableWorkflow
    /// Newest first, as the API returns them.
    public let runs: [WorkflowRunSummary]

    public var id: String { workflow.id }

    public init(workflow: DispatchableWorkflow, runs: [WorkflowRunSummary]) {
        self.workflow = workflow
        self.runs = runs
    }

    public var latest: WorkflowRunSummary? { runs.first }

    /// Runs that reached a conclusion. Everything below is computed over these:
    /// a run still in flight has no duration and no verdict, and counting it
    /// would make the pass rate wobble while you watch.
    public var completed: [WorkflowRunSummary] {
        runs.filter { !$0.status.isOpen && $0.status != .never }
    }

    /// Cancelled runs are excluded from both halves: a run somebody stopped is
    /// not evidence about the workflow either way.
    public var judged: [WorkflowRunSummary] {
        completed.filter { $0.status == .succeeded || $0.status == .failed }
    }

    public var successCount: Int { judged.filter { $0.status == .succeeded }.count }
    public var failureCount: Int { judged.filter { $0.status == .failed }.count }

    /// Nil rather than 1.0 when there is nothing to judge, so "no history" and
    /// "never failed" stay distinguishable on screen.
    public var successRate: Double? {
        guard !judged.isEmpty else { return nil }
        return Double(successCount) / Double(judged.count)
    }

    /// Median, not mean: one twenty-minute run that hit a retry should not move
    /// the number a whole screen is read through.
    public var medianDuration: TimeInterval? {
        let durations = judged.compactMap { $0.duration(now: Date()) }.sorted()
        guard !durations.isEmpty else { return nil }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }

    public var longestDuration: TimeInterval? {
        judged.compactMap { $0.duration(now: Date()) }.max()
    }

    public var lastSuccessAt: Date? {
        runs.first { $0.status == .succeeded }.flatMap { $0.finishedAt ?? $0.startedAt }
    }

    public var lastFailureAt: Date? {
        runs.first { $0.status == .failed }.flatMap { $0.finishedAt ?? $0.startedAt }
    }

    /// How many of these runs started in the last week — the cadence line under
    /// a card, which for Update is really "how often did something deploy".
    public func runsSince(_ date: Date) -> Int {
        runs.filter { ($0.startedAt ?? .distantPast) >= date }.count
    }

    /// Oldest first, which is the direction a chart reads. Carries its own
    /// index so bars stay put when two runs share a start time and so a chart
    /// has something stable to identify them by.
    public var bars: [RunBar] {
        completed
            .reversed()
            .enumerated()
            .map { index, run in
                RunBar(
                    index: index,
                    identifier: run.identifier,
                    status: run.status,
                    duration: run.duration(now: Date()) ?? 0,
                    startedAt: run.startedAt,
                    url: run.url
                )
            }
    }

    /// Whether the recent half is slower than the older half, by enough to be
    /// worth an arrow. Nil when there are too few runs to say anything.
    public var durationTrend: Double? {
        let durations = completed.compactMap { $0.duration(now: Date()) }
        guard durations.count >= 4 else { return nil }

        let half = durations.count / 2
        // `durations` is newest first, so the front half is the recent one.
        let recent = Array(durations.prefix(half))
        let older = Array(durations.suffix(half))

        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let olderMean = older.reduce(0, +) / Double(older.count)
        guard olderMean > 0 else { return nil }
        return (recentMean - olderMean) / olderMean
    }
}

/// One bar of the run-duration chart.
public struct RunBar: Equatable, Sendable, Codable, Identifiable {
    public let index: Int
    public let identifier: Int
    public let status: RunStatus
    public let duration: TimeInterval
    public let startedAt: Date?
    public let url: URL

    public var id: Int { identifier }

    public init(
        index: Int,
        identifier: Int,
        status: RunStatus,
        duration: TimeInterval,
        startedAt: Date?,
        url: URL
    ) {
        self.index = index
        self.identifier = identifier
        self.status = status
        self.duration = duration
        self.startedAt = startedAt
        self.url = url
    }
}

/// Every workflow's history together, plus the cross-workflow numbers the home
/// screen leads with.
public struct ActivityHistory: Equatable, Sendable, Codable {
    public var histories: [RunHistory]
    public var lastRefreshedAt: Date?

    public init(histories: [RunHistory] = [], lastRefreshedAt: Date? = nil) {
        self.histories = histories
        self.lastRefreshedAt = lastRefreshedAt
    }

    public var isEmpty: Bool { histories.allSatisfy { $0.runs.isEmpty } }

    public func history(for workflow: DispatchableWorkflow) -> RunHistory? {
        histories.first { $0.workflow == workflow }
    }

    /// Pass rate across every workflow, which is the one number on the home
    /// screen that says whether this week went well.
    public var successRate: Double? {
        let judged = histories.flatMap(\.judged)
        guard !judged.isEmpty else { return nil }
        let succeeded = judged.filter { $0.status == .succeeded }.count
        return Double(succeeded) / Double(judged.count)
    }

    public func runCount(since date: Date) -> Int {
        histories.reduce(0) { $0 + $1.runsSince(date) }
    }

    /// Deploys specifically — every push to `main` runs Update, so this is the
    /// honest answer to "how much changed this week".
    public func deployCount(since date: Date) -> Int {
        history(for: .update)?.runsSince(date) ?? 0
    }

    /// Every completed run across every workflow, newest first — the activity
    /// timeline on the home screen.
    public var timeline: [TimelineEntry] {
        histories
            .flatMap { history in
                history.runs.map { TimelineEntry(workflow: history.workflow, run: $0) }
            }
            .sorted { ($0.run.startedAt ?? .distantPast) > ($1.run.startedAt ?? .distantPast) }
    }

    public struct TimelineEntry: Equatable, Sendable, Codable, Identifiable {
        public let workflow: DispatchableWorkflow
        public let run: WorkflowRunSummary

        public var id: Int { run.identifier }

        public init(workflow: DispatchableWorkflow, run: WorkflowRunSummary) {
            self.workflow = workflow
            self.run = run
        }
    }
}
