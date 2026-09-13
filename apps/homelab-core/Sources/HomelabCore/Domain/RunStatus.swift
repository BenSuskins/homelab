import Foundation

/// The state of the most recent run of a Dispatchable Workflow on `main`.
public enum RunStatus: String, Equatable, Sendable, Codable {
    /// The workflow has never run on `main`.
    case never
    case queued
    case running
    /// Parked at an environment gate, waiting for a required reviewer.
    /// Terraform's apply stage does this on every run.
    case awaitingApproval
    case succeeded
    case failed
    case cancelled

    /// GitHub splits this across two fields: a `status` that is only ever
    /// `completed` for finished runs, and a `conclusion` that is null until then.
    public init(status: String, conclusion: String?) {
        switch status {
        case "completed":
            switch conclusion {
            case "success", "skipped", "neutral": self = .succeeded
            case "cancelled": self = .cancelled
            case "action_required": self = .awaitingApproval
            default: self = .failed
            }
        case "waiting", "pending", "action_required":
            self = .awaitingApproval
        case "in_progress":
            self = .running
        default:
            self = .queued
        }
    }

    /// Whether GitHub is currently doing work — the only condition that
    /// justifies the fast polling interval.
    public var isActive: Bool {
        self == .queued || self == .running
    }

    /// A run that has not reached a conclusion still owns the workflow, so
    /// starting another would race it.
    public var isOpen: Bool {
        isActive || self == .awaitingApproval
    }
}
