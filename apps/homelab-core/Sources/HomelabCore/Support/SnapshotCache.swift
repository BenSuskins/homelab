import Foundation

/// Persists the last snapshot so a surface has something to draw the instant it
/// opens, rather than an empty box for the length of a round trip.
///
/// On iOS it does a second job: the app and the widget extension are separate
/// processes with separate containers, so pointing both at an App Group is what
/// lets a widget render real data before it has fetched anything — and what
/// lets it render at all when the device is locked and the token in the
/// Keychain is unreadable.
public struct SnapshotCache: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    /// Shared between the app and its widget. Falls back to the process's own
    /// Application Support directory if the group is not configured, so a
    /// missing entitlement degrades to a private cache rather than a crash.
    public init(appGroup identifier: String) {
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            self.fileURL = container
                .appendingPathComponent("HomelabCore", isDirectory: true)
                .appendingPathComponent("snapshot.json")
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return base
            .appendingPathComponent("HomelabMenuBar", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    public func load() -> StatusSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(StatusSnapshot.self, from: data)
    }

    public func save(_ snapshot: StatusSnapshot) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
