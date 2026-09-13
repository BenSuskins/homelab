import Foundation

/// Nothing changes for hours, then everything changes for four minutes — so the
/// interval follows the work rather than the clock.
public enum PollingSchedule {
    public static let idle: Duration = .seconds(300)
    public static let active: Duration = .seconds(10)

    public static func interval(for snapshot: StatusSnapshot) -> Duration {
        snapshot.hasActiveRun ? active : idle
    }
}

/// Which runs newly reached a failed conclusion, and therefore deserve a
/// notification. Comparing whole snapshots keeps this a pure function of two
/// values rather than a pile of mutable "have I already told them" flags.
public enum FailureDetector {
    public static func newFailures(
        previous: StatusSnapshot?,
        current: StatusSnapshot
    ) -> [RunRow] {
        // Without a previous snapshot every existing failure looks new, which
        // would fire a notification for last week's breakage on every launch.
        guard let previous else { return [] }

        return current.runRows.filter { row in
            guard row.status == .failed, let run = row.run else { return false }

            guard let earlier = previous.row(for: row.workflow), let earlierRun = earlier.run
            else { return true }

            return earlierRun.identifier != run.identifier || earlier.status != .failed
        }
    }
}
