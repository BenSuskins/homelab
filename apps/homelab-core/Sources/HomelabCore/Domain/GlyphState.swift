import Foundation

/// What the menu bar icon shows when the menu is closed. It answers exactly one
/// question — "do I need to open this?" — so the three run rows collapse into
/// the worst thing any of them is doing.
public enum GlyphState: String, Equatable, Sendable, Codable {
    case ok
    case running
    case failed

    public static func worstOf(_ statuses: [RunStatus]) -> GlyphState {
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(where: \.isActive) { return .running }
        return .ok
    }

    public var symbolName: String {
        switch self {
        case .ok: "server.rack"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
