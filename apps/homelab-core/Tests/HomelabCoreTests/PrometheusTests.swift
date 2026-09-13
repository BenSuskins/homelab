import Foundation
import Testing
@testable import HomelabCore

/// `.serialized` for the same reason as the device flow suite: `StubURLProtocol`
/// holds its canned response in static storage, so two tests running at once
/// would answer each other's requests.
@Suite("Prometheus decoding", .serialized)
struct PrometheusDecodingTests {
    /// The decoding is exercised through a stubbed `URLProtocol` rather than a
    /// faked client, because the awkward part is the wire format itself: a
    /// sample is `[<unix seconds>, "<value as a string>"]`, a heterogeneous
    /// array that no synthesised `Decodable` will handle.
    private func client(responding body: String, status: Int = 200) -> PrometheusClient {
        PrometheusClient(
            baseURL: URL(string: "http://prometheus.test:9090")!,
            session: StubURLProtocol.session(body: body, status: status)
        )
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
        let client = PrometheusClient(
            baseURL: URL(string: "http://prometheus.test:9090")!,
            session: StubURLProtocol.failingSession()
        )

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

/// A `URLProtocol` that answers every request from a canned string, so the
/// client's real `URLSession` path is what runs.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body: String = "{}"
    nonisolated(unsafe) static var status: Int = 200
    nonisolated(unsafe) static var shouldFail = false

    static func session(body: String, status: Int) -> URLSession {
        Self.body = body
        Self.status = status
        Self.shouldFail = false
        return makeSession()
    }

    static func failingSession() -> URLSession {
        Self.shouldFail = true
        return makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
