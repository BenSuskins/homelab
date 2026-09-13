import Foundation

/// One row of the run list. Every question the view can ask — what colour, is
/// the button enabled, what does the subtitle say — is answered here, so the
/// view holds no logic and the logic needs no view to be tested.
public struct RunRow: Equatable, Sendable, Codable, Identifiable {
    public let workflow: DispatchableWorkflow
    public let status: RunStatus
    public let run: WorkflowRunSummary?

    public var id: String { workflow.id }

    public var canTrigger: Bool { !status.isOpen }
    public var canCancel: Bool { status.isOpen }

    public init(workflow: DispatchableWorkflow, run: WorkflowRunSummary?) {
        self.workflow = workflow
        self.run = run
        self.status = run?.status ?? .never
    }
}

/// An immutable description of everything a surface renders — the macOS menu,
/// the iOS runs tab, the widget. Produced by a pure function from fetched data,
/// consumed by SwiftUI, and persisted verbatim so each of them paints instantly
/// at launch instead of showing an empty box for a round trip.
///
/// It was called `MenuSnapshot` while there was only a menu.
public struct StatusSnapshot: Equatable, Sendable, Codable {
    public var runRows: [RunRow]
    public var pullRequests: [PullRequestSummary]
    public var lastRefreshedAt: Date?
    public var errorMessage: String?

    public init(
        runRows: [RunRow] = [],
        pullRequests: [PullRequestSummary] = [],
        lastRefreshedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.runRows = runRows
        self.pullRequests = pullRequests
        self.lastRefreshedAt = lastRefreshedAt
        self.errorMessage = errorMessage
    }

    public var glyph: GlyphState {
        GlyphState.worstOf(runRows.map(\.status))
    }

    public var hasActiveRun: Bool {
        runRows.contains { $0.status.isActive }
    }

    public func row(for workflow: DispatchableWorkflow) -> RunRow? {
        runRows.first { $0.workflow == workflow }
    }

    /// The empty state shown before the first refresh lands, so the rows never
    /// pop into existence one at a time.
    public static var placeholder: StatusSnapshot {
        StatusSnapshot(
            runRows: DispatchableWorkflow.allCases.map { RunRow(workflow: $0, run: nil) }
        )
    }

    public static func make(
        runs: [DispatchableWorkflow: WorkflowRunSummary],
        pullRequests: [PullRequestSummary],
        lastRefreshedAt: Date?,
        errorMessage: String? = nil
    ) -> StatusSnapshot {
        StatusSnapshot(
            runRows: DispatchableWorkflow.allCases.map {
                RunRow(workflow: $0, run: runs[$0])
            },
            pullRequests: pullRequests.sorted { $0.number > $1.number },
            lastRefreshedAt: lastRefreshedAt,
            errorMessage: errorMessage
        )
    }
}
