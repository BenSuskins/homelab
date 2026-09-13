import SwiftUI

/// How each run state looks and reads. Kept beside the domain rather than
/// inside the view so the whole vocabulary is visible in one place.
public struct RunStatusPresentation: Sendable {
    public let symbolName: String
    public let tint: Color
    public let label: String

    public init(_ status: RunStatus) {
        switch status {
        case .never:
            self.init(symbol: "minus.circle", tint: .secondary, label: "never run")
        case .queued:
            self.init(symbol: "clock", tint: .secondary, label: "queued")
        case .running:
            self.init(symbol: "circle.dotted", tint: .accentColor, label: "running")
        case .awaitingApproval:
            self.init(symbol: "pause.circle.fill", tint: .orange, label: "awaiting approval")
        case .succeeded:
            self.init(symbol: "checkmark.circle.fill", tint: .green, label: "passed")
        case .failed:
            self.init(symbol: "xmark.circle.fill", tint: .red, label: "failed")
        case .cancelled:
            self.init(symbol: "slash.circle", tint: .secondary, label: "cancelled")
        }
    }

    private init(symbol: String, tint: Color, label: String) {
        self.symbolName = symbol
        self.tint = tint
        self.label = label
    }
}

extension RunRow {
    public var presentation: RunStatusPresentation { RunStatusPresentation(status) }

    /// "2h ago", "running · 3m 12s", "awaiting approval · plan ready".
    public func subtitle(now: Date = Date()) -> String {
        guard let run else { return "never run on main" }

        switch status {
        case .running, .queued:
            let elapsed = run.duration(now: now).map(RelativeTime.duration) ?? "—"
            return "\(presentation.label) · \(elapsed)"
        case .awaitingApproval:
            return "awaiting approval · plan ready"
        default:
            let when = (run.finishedAt ?? run.startedAt).map { RelativeTime.ago($0, now: now) }
            let elapsed = run.duration(now: now).map(RelativeTime.duration)
            return [presentation.label, when, elapsed]
                .compactMap(\.self)
                .joined(separator: " · ")
        }
    }
}
