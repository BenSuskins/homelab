import Foundation
import Testing
@testable import HomelabCore

@MainActor
@Suite("Monitor refresh")
struct MonitorRefreshTests {
    @Test("the launch refresh loads every screen without opening its tab")
    func sessionRefreshLoadsEveryScreen() async {
        let endpoint = RefreshURLProtocol.endpoint()
        await endpoint.gate.open()
        let session = Session(
            configuration: .iOS,
            tokens: InMemoryTokenStore(token: "test-token"),
            cache: SnapshotCache(fileURL: URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")),
            healthMonitor: HealthMonitor(client: PrometheusClient(baseURL: endpoint.url, session: endpoint.session)),
            logMonitor: LogMonitor(client: LokiClient(baseURL: endpoint.url, session: endpoint.session)),
            transport: FakeTransport()
        )
        await session.restore()
        await session.refresh()

        #expect(session.appState?.snapshot.lastRefreshedAt != nil)
        #expect(session.healthMonitor.snapshot.lastRefreshedAt != nil)
        #expect(session.logMonitor.snapshot.lastRefreshedAt != nil)
    }

    @Test("a Health pull waits for the current refresh")
    func healthPullWaits() async {
        let endpoint = RefreshURLProtocol.endpoint()
        let monitor = HealthMonitor(client: PrometheusClient(baseURL: endpoint.url, session: endpoint.session))
        await checkOverlappingRefresh(gate: endpoint.gate) {
            await monitor.refresh()
            return monitor.snapshot.lastRefreshedAt
        }
    }

    @Test("a Logs pull waits for the current refresh")
    func logsPullWaits() async {
        let endpoint = RefreshURLProtocol.endpoint()
        let monitor = LogMonitor(client: LokiClient(baseURL: endpoint.url, session: endpoint.session))
        await checkOverlappingRefresh(gate: endpoint.gate) {
            await monitor.refresh()
            return monitor.snapshot.lastRefreshedAt
        }
    }

    @Test("a window change during a Health refresh loads the selected window")
    func healthKeepsLatestWindow() async {
        let endpoint = RefreshURLProtocol.endpoint()
        let monitor = HealthMonitor(client: PrometheusClient(baseURL: endpoint.url, session: endpoint.session))
        let first = Task { await monitor.refresh() }
        await endpoint.gate.waitUntilEntered()
        var selection: Task<Void, Never>?
        await withCheckedContinuation { started in
            selection = Task { @MainActor in
                started.resume()
                await monitor.select(.hour)
            }
        }
        await endpoint.gate.open()
        await first.value
        await selection?.value

        #expect(monitor.history.window == .hour)
        #expect(monitor.failure == nil)
    }

    @Test("a filter change during a Logs refresh loads the selected host")
    func logsKeepLatestHost() async {
        let endpoint = RefreshURLProtocol.endpoint()
        let monitor = LogMonitor(client: LokiClient(baseURL: endpoint.url, session: endpoint.session))
        let first = Task { await monitor.refresh() }
        await endpoint.gate.waitUntilEntered()
        monitor.selectedHost = "new-host"
        let second = Task { await monitor.refresh() }
        await endpoint.gate.open()
        await first.value
        await second.value

        let query = endpoint.requests().last { $0.path.contains("query_range") }
        let selector = query.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "query" }?.value
        #expect(selector?.contains("new-host") == true)
        #expect(monitor.failure == nil)
    }

    private func checkOverlappingRefresh(
        gate: RequestGate,
        refresh: @escaping @MainActor () async -> Date?
    ) async {
        let first = Task { await refresh() }
        await gate.waitUntilEntered()
        var returnedBeforeData = false
        var second: Task<Void, Never>?
        await withCheckedContinuation { started in
            second = Task { @MainActor in
                started.resume()
                returnedBeforeData = await refresh() == nil
            }
        }
        await gate.open()
        _ = await first.value
        await second?.value
        #expect(returnedBeforeData == false)
    }
}

final class RefreshURLProtocol: URLProtocol, @unchecked Sendable {
    struct Endpoint {
        let url: URL
        let session: URLSession
        let gate: RequestGate

        func requests() -> [URL] {
            RefreshURLProtocol.lock.withLock { RefreshURLProtocol.recorded[url.host!] ?? [] }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var gates: [String: RequestGate] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URL]] = [:]

    static func endpoint() -> Endpoint {
        let host = "refresh-\(UUID().uuidString.lowercased()).test"
        let gate = RequestGate()
        lock.withLock { gates[host] = gate }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshURLProtocol.self]
        return Endpoint(
            url: URL(string: "http://\(host)")!,
            session: URLSession(configuration: configuration),
            gate: gate
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let gate = Self.lock.withLock {
            Self.recorded[url.host!, default: []].append(url)
            return Self.gates[url.host!]
        }
        Task { @Sendable [self, gate, url] in
            await gate?.wait()
            let body: String
            if url.path.contains("/label/") {
                body = #"{"status":"success","data":[]}"#
            } else if url.path.contains("/loki/") {
                body = #"{"status":"success","data":{"resultType":"streams","result":[]}}"#
            } else {
                body = #"{"status":"success","data":{"resultType":"matrix","result":[]}}"#
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
