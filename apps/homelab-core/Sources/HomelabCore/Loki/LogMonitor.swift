import Foundation
import Observation

public struct LogSnapshot: Sendable, Equatable {
    public let entries: [LokiLogEntry]
    public let hosts: [String]
    public let containers: [String]
    public let lastRefreshedAt: Date?

    public init(
        entries: [LokiLogEntry] = [],
        hosts: [String] = [],
        containers: [String] = [],
        lastRefreshedAt: Date? = nil
    ) {
        self.entries = entries
        self.hosts = hosts
        self.containers = containers
        self.lastRefreshedAt = lastRefreshedAt
    }
}

@MainActor
@Observable
public final class LogMonitor {
    /// How many lines a single read asks Loki for. Also the ceiling the live
    /// tail trims the buffer back to.
    public static let lineLimit = 500

    public private(set) var snapshot = LogSnapshot()
    public private(set) var isRefreshing = false
    public private(set) var isTailing = false
    public private(set) var failure: LokiFailure?

    public var selectedHost: String?
    public var selectedContainer: String?
    public var range: TimeInterval = 3600

    /// Applied here rather than in the query, because there is no level label
    /// to select on — Alloy ships container stdout verbatim. So the window is
    /// fetched whole and narrowed on the device.
    public var selectedLevel: LogLevel?
    public var search: String = ""

    private let client: LokiClient
    private var tailTask: Task<Void, Never>?

    public init(client: LokiClient = LokiClient()) {
        self.client = client
    }

    public var isOffTailnet: Bool {
        if case .unreachable = failure { return true }
        return false
    }

    public var query: String {
        LokiClient.selector(host: selectedHost, container: selectedContainer)
    }

    /// Newest first: a log you opened on a phone is a log you are reading
    /// because something just happened.
    public var visibleEntries: [LokiLogEntry] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return snapshot.entries.reversed().filter { entry in
            if let selectedLevel, entry.record.level != selectedLevel { return false }
            guard !term.isEmpty else { return true }
            return entry.line.lowercased().contains(term)
                || entry.container?.lowercased().contains(term) == true
        }
    }

    /// How many lines of each level the window holds, before the level filter
    /// is applied — so the chips keep showing the counts you are choosing
    /// between rather than collapsing to one number and a zero.
    public var levelCounts: [LogLevel: Int] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return snapshot.entries.reduce(into: [:]) { counts, entry in
            guard term.isEmpty || entry.line.lowercased().contains(term) else { return }
            counts[entry.record.level, default: 0] += 1
        }
    }

    public var hasFilters: Bool {
        selectedHost != nil || selectedContainer != nil || selectedLevel != nil
            || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func clearFilters() {
        selectedHost = nil
        selectedContainer = nil
        selectedLevel = nil
        search = ""
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let end = Date()
        let start = end.addingTimeInterval(-range)

        do {
            // Over the same window as the entries, so the pickers cannot offer
            // a container the query will not return and cannot omit one it will.
            async let hosts = client.labelValues("host", start: start, end: end)
            async let containers = client.labelValues("container", start: start, end: end)
            let entries = try await client.queryRange(
                query,
                start: start,
                end: end,
                limit: Self.lineLimit
            )
            snapshot = LogSnapshot(
                entries: entries,
                // The pickers are a convenience and the lines are the point, so
                // a label read that fails keeps the last known values rather
                // than emptying the screen.
                hosts: (try? await hosts) ?? snapshot.hosts,
                containers: (try? await containers) ?? snapshot.containers,
                lastRefreshedAt: Date()
            )
            failure = nil
        } catch let error as LokiFailure {
            failure = error
        } catch {
            failure = .malformedResponse(String(describing: error))
        }
    }

    public func setTailing(_ enabled: Bool) {
        if enabled {
            startTail()
        } else {
            stopTail()
        }
    }

    public func stopTail() {
        tailTask?.cancel()
        tailTask = nil
        isTailing = false
    }

    private func startTail() {
        stopTail()
        isTailing = true
        let client = self.client
        let query = self.query
        // From now, not from the start of the window: the window is already on
        // screen, and replaying it would double every line in the list.
        let start = Date()
        tailTask = Task { [weak self] in
            do {
                for try await entry in client.tail(query, start: start) {
                    guard !Task.isCancelled else { return }
                    self?.append(entry)
                }
            } catch let error as LokiFailure {
                self?.recordTailFailure(error)
            } catch {
                self?.recordTailFailure(.unreachable(String(describing: error)))
            }
            self?.tailStopped()
        }
    }

    private func append(_ entry: LokiLogEntry) {
        // Loki can re-deliver around a reconnect, and two rows with one `id`
        // makes SwiftUI's `ForEach` misbehave rather than merely look wrong.
        guard !snapshot.entries.contains(where: { $0.id == entry.id }) else { return }

        snapshot = LogSnapshot(
            entries: (snapshot.entries + [entry]).suffix(Self.lineLimit),
            hosts: snapshot.hosts,
            containers: snapshot.containers,
            lastRefreshedAt: snapshot.lastRefreshedAt
        )
    }

    private func recordTailFailure(_ error: LokiFailure) {
        failure = error
    }

    private func tailStopped() {
        if !Task.isCancelled { isTailing = false }
    }
}
