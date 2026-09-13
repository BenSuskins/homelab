import Foundation

public enum RelativeTime {
    /// "2h ago", "3d ago" — deliberately coarse, because the menu answers
    /// "recently or not" rather than "exactly when".
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3_600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    /// "4m 01s" — used for run durations, where seconds genuinely matter
    /// while you are watching one tick upward.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds)s" }
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
