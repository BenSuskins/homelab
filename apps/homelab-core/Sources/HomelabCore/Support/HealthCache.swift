import Foundation

/// The health screen's half of what `SnapshotCache` does for runs: the last
/// reading, on disk in the App Group, so the health widget has something true
/// to draw when it wakes up off the tailnet — which is most of the time, since
/// a widget refresh is scheduled by iOS rather than by anyone holding the phone.
///
/// Only the snapshot is cached, not the history: a week of range-query points
/// is megabytes, and a chart with no data is a legible empty state whereas a
/// stale chart is a lie with axes on it.
public struct HealthCache: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Shared between the app and its widgets. Falls back to the process's own
    /// Application Support directory if the group is not configured, so a
    /// missing entitlement degrades to a private cache rather than a crash.
    public init(appGroup identifier: String) {
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            self.fileURL = container
                .appendingPathComponent("HomelabCore", isDirectory: true)
                .appendingPathComponent("health.json")
        } else {
            self.fileURL = SnapshotCache.defaultFileURL()
                .deletingLastPathComponent()
                .appendingPathComponent("health.json")
        }
    }

    public func load() -> HealthSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONCoding.decoder.decode(HealthSnapshot.self, from: data)
    }

    public func save(_ snapshot: HealthSnapshot) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONCoding.encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// One encoder and one decoder for everything this package persists, so two
/// caches cannot drift onto different date strategies and fail to read each
/// other's files.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
