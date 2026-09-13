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
    public private(set) var snapshot = LogSnapshot()
    public private(set) var isRefreshing = false
    public private(set) var isTailing = false
    public private(set) var failure: LokiFailure?

    public var selectedHost: String?
    public var selectedContainer: String?
    public var range: TimeInterval = 3600

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

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let hosts = client.labelValues("host")
            async let containers = client.labelValues("container")
            let entries = try await client.queryRange(
                query,
                start: Date().addingTimeInterval(-range),
                limit: 500
            )
            snapshot = LogSnapshot(
                entries: entries,
                hosts: try await hosts,
                containers: try await containers,
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
        let client: LokiClient
        let query: String
        let start = Date().addingTimeInterval(-range)
        client = self.client
        query = self.query
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
        snapshot = LogSnapshot(
            entries: (snapshot.entries + [entry]).suffix(500),
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
