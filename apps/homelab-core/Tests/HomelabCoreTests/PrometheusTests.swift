import Foundation
import Testing
@testable import HomelabCore

@Suite("Prometheus decoding")
struct PrometheusDecodingTests {
    /// The decoding is exercised through a stubbed `URLProtocol` rather than a
    /// faked client, because the awkward part is the wire format itself: a
    /// sample is `[<unix seconds>, "<value as a string>"]`, a heterogeneous
    /// array that no synthesised `Decodable` will handle.
    ///
    /// No `.serialized` trait: each stub owns a host, so nothing is shared for
    /// a parallel test to trample.
    private func client(responding body: String, status: Int = 200) -> PrometheusClient {
        let stub = StubURLProtocol.stub(body: body, status: status)
        return PrometheusClient(baseURL: stub.url, session: stub.session)
    }

    @Test("decodes a vector, including the string-encoded value")
    func decodesVector() async throws {
        let samples = try await client(responding: Samples.gatusResults)
            .instantQuery("gatus_results_endpoint_success")

        #expect(samples.count == 3)
        #expect(samples[0]["name"] == "plex")
        #expect(samples[0].value == 1)
        #expect(samples[1].value == 0)
    }

    @Test("reports a rejected query rather than returning nothing")
    func reportsQueryError() async {
        await #expect(throws: PrometheusFailure.self) {
            try await client(responding: Samples.prometheusError).instantQuery("nonsense{")
        }
    }

    @Test("an unreachable Prometheus is its own failure, not a generic one")
    func unreachableIsDistinct() async {
        let stub = StubURLProtocol.failing()
        let client = PrometheusClient(baseURL: stub.url, session: stub.session)

        do {
            _ = try await client.instantQuery("up")
            Issue.record("Expected a failure")
        } catch {
            // Off the tailnet is the expected state of a phone, so it must be
            // distinguishable from Prometheus being broken.
            guard case .unreachable = error else {
                Issue.record("Expected .unreachable, got \(error)")
                return
            }
            #expect(error.displayMessage == "Not connected to the tailnet")
        }
    }

    @Test("a non-2xx status is a rejected query, not an unreachable host")
    func httpErrorIsNotUnreachable() async {
        do {
            _ = try await client(responding: "{}", status: 422).instantQuery("up")
            Issue.record("Expected a failure")
        } catch {
            guard case .queryRejected = error else {
                Issue.record("Expected .queryRejected, got \(error)")
                return
            }
        }
    }
}

@Suite("Health snapshot")
struct HealthSnapshotTests {
    @Test("counts what is down and groups the rest by Host Label")
    func groupsByHost() {
        let snapshot = HealthSnapshot(services: [
            ServiceHealth(name: "sonarr", host: "Media", isUp: false),
            ServiceHealth(name: "plex", host: "Media", isUp: true),
            ServiceHealth(name: "grafana", host: "Monitoring", isUp: true),
        ])

        #expect(snapshot.downCount == 1)
        #expect(snapshot.servicesByHost.map(\.host) == ["Media", "Monitoring"])
        #expect(snapshot.servicesByHost[0].services.map(\.name) == ["plex", "sonarr"])
    }

    @Test("combines three separate queries into one row per host")
    func combinesHostMetrics() {
        let hosts = HealthMonitor.combine(
            load: [
                PrometheusSample(labels: ["host": "Media"], value: 1.5),
                PrometheusSample(labels: ["host": "Docker"], value: 0.2),
            ],
            memory: [PrometheusSample(labels: ["host": "Media"], value: 0.61)],
            disk: [PrometheusSample(labels: ["host": "Monitoring"], value: 0.44)]
        )

        #expect(hosts.map(\.host) == ["Docker", "Media", "Monitoring"])
        #expect(hosts[1].load1 == 1.5)
        #expect(hosts[1].memoryUsedFraction == 0.61)
        // A host present in one query and absent from another still gets a row,
        // with the missing number left nil rather than defaulted to zero.
        #expect(hosts[1].rootDiskUsedFraction == nil)
        #expect(hosts[0].memoryUsedFraction == nil)
    }

    @Test("drops samples with no Host Label rather than inventing one")
    func ignoresUnlabelledSamples() {
        // ADR-0001: `host` is the only label that identifies a host. A series
        // without one cannot be attributed, and `instance` is not a substitute.
        let hosts = HealthMonitor.combine(
            load: [PrometheusSample(labels: ["instance": "192.168.0.201:12345"], value: 9)],
            memory: [],
            disk: []
        )

        #expect(hosts.isEmpty)
    }

    @Test("treats NaN as missing rather than as a reading of zero")
    func ignoresNaN() {
        let hosts = HealthMonitor.combine(
            load: [PrometheusSample(labels: ["host": "Media"], value: .nan)],
            memory: [PrometheusSample(labels: ["host": "Media"], value: 0.5)],
            disk: []
        )

        #expect(hosts.count == 1)
        #expect(hosts[0].load1 == nil)
        #expect(hosts[0].memoryUsedFraction == 0.5)
    }
}

@Suite("Loki logs")
struct LokiTests {
    @Test("decodes streams into chronological log entries")
    func decodesStreams() throws {
        let entries = try LokiClient.decodeEntries(from: Data(Samples.lokiQuery.utf8))

        #expect(entries.map(\.line) == ["started", "warning", "ready"])
        #expect(entries.map(\.container) == ["api", "worker", "api"])
        #expect(entries.map(\.host) == ["Docker", "Media", "Docker"])
    }

    @Test("builds a label selector from host and container")
    func buildsSelector() {
        #expect(LokiClient.selector(host: "Docker", container: "api") == "{host=\"Docker\", container=\"api\"}")
        #expect(LokiClient.selector(host: nil, container: nil) == "{container=~\".+\"}")
    }

    @Test("decodes label values")
    func decodesLabelValues() throws {
        let values = try LokiClient.decodeLabelValues(from: Data(Samples.lokiLabelValues.utf8))

        #expect(values == ["Docker", "Media"])
    }
}

/// A `URLProtocol` that answers every request from a canned string.
///
/// Each stub mints a host of its own and registers its response under it, so
/// two suites running at the same time cannot answer each other's requests.
/// It held one static response until there was a second Prometheus suite, at
/// which point `.serialized` stopped being enough: that trait orders the tests
/// *within* a suite, and the suites themselves still ran in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stubbed {
        let url: URL
        let session: URLSession
    }

    private struct Response {
        let body: String
        let status: Int
        let shouldFail: Bool
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func stub(body: String, status: Int = 200) -> Stubbed {
        register(Response(body: body, status: status, shouldFail: false))
    }

    static func failing() -> Stubbed {
        register(Response(body: "", status: 0, shouldFail: true))
    }

    private static func register(_ response: Response) -> Stubbed {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        lock.withLock { responses[host] = response }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]

        return Stubbed(
            url: URL(string: "http://\(host):9090")!,
            session: URLSession(configuration: configuration)
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host ?? ""
        guard let response = Self.lock.withLock({ Self.responses[host] }) else {
            // An unregistered host is a test wiring mistake, not a network
            // condition, so it fails loudly rather than looking like an outage.
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if response.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
