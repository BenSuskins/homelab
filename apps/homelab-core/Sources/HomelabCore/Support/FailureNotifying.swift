import Foundation

public protocol FailureNotifying: Sendable {
    func requestAuthorization() async
    func notify(_ row: RunRow) async
}

/// The default, and the only one iOS gets. `UNUserNotificationCenter` exists on
/// both platforms, which makes porting the macOS notifier the obvious move and
/// the wrong one: a backgrounded iOS app is suspended within seconds, so the
/// polling loop stops, `FailureDetector` never sees the failure, and the
/// notification could only ever fire while you were already looking at the app.
///
/// The concrete notifier therefore lives in the macOS target, so this is not a
/// convention the iOS app is trusted to remember — the type is not there to
/// wire up. See ADR-0005.
public struct SilentFailureNotifier: FailureNotifying {
    public init() {}
    public func requestAuthorization() async {}
    public func notify(_ row: RunRow) async {}
}
