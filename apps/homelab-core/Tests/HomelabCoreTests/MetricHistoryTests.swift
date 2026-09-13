import Foundation
import Testing
@testable import HomelabCore

/// `.serialized` for the same reason as the other Prometheus suite:
/// `StubURLProtocol` holds its canned response in static storage.
@Suite("Prometheus range queries", .serialized)
struct PrometheusRangeTests {
    private func client(responding body: String, status: Int = 200) -> PrometheusClient {
        PrometheusClient(
            baseURL: URL(string: "http://prometheus.test:9090")!,
            session: StubURLProtocol.session(body: body, status: status)
        )
    }

    @Test("decodes a matrix into one series per label set")
    func decodesMatrix() async throws {
        let series = try await client(responding: Samples.nodeLoadMatrix)
            .rangeQuery("node_load1", window: .hour)

        #expect(series.count == 2)
        #expect(series[0].host == "Media")
        #expect(series[1].host == "Docker")
    }

    @Test("treats a NaN mid-line as a gap, not as a reading of zero")
    func dropsNaNPoints() async throws {
        let series = try await client(responding: Samples.nodeLoadMatrix)
            .rangeQuery("node_load1", window: .hour)

        // Four samples arrive, one of them "NaN". A zero there would draw as a
        // cliff on the chart and read as a real measurement.
        #expect(series[0].points.count == 3)
        #expect(series[0].points.map(\.value) == [0.4, 1.2, 0.8])
        #expect(series[0].latest == 0.8)
        #expect(series[0].peak == 1.2)
    }

    @Test("the last point is what a tile shows")
    func exposesSummaries() async throws {
        let series = try await client(responding: Samples.nodeLoadMatrix)
            .rangeQuery("node_load1", window: .hour)

        #expect(series[1].latest == 3.5)
        #expect(series[1].mean == 3.0)
        // First 2.5, last 3.5 — up 40% across the window.
        let trend = try #require(series[1].trend)
        #expect(abs(trend - 0.4) < 0.0001)
    }

    @Test("a rejected range query fails like any other query")
    func reportsQueryError() async {
        await #expect(throws: PrometheusFailure.self) {
            try await client(responding: Samples.prometheusError)
                .rangeQuery("nonsense{", window: .hour)
        }
    }

    @Test("an instant query still decodes a vector after the shared refactor")
    func vectorStillDecodes() async throws {
        let samples = try await client(responding: Samples.gatusResults)
            .instantQuery(HealthQuery.serviceSuccess)

        #expect(samples.count == 3)
        #expect(samples[1].value == 0)
    }
}

@Suite("Metric window")
struct MetricWindowTests {
    @Test("every window samples a chartable number of points")
    func windowsProduceSaneStepCounts() {
        for window in MetricWindow.allCases {
            let points = window.duration / window.step
            // Enough to show shape, few enough that a phone renders it and
            // Prometheus is not asked for thousands of samples.
            #expect(points >= 100)
            #expect(points <= 200)
        }
    }

    @Test("the rate interval is always several steps wide")
    func rateIntervalsCoverTheStep() {
        // `rate()` over a window narrower than the scrape interval returns
        // nothing at all, which shows up as an empty chart rather than an error.
        #expect(MetricWindow.hour.rateInterval == "2m")
        #expect(MetricWindow.week.rateInterval == "1h")
    }
}

@Suite("Health history")
struct HealthHistoryTests {
    private func series(host: String, values: [Double]) -> MetricSeries {
        MetricSeries(
            labels: ["host": host],
            points: values.enumerated().map { index, value in
                MetricPoint(
                    date: Date(timeIntervalSince1970: 1_757_779_200 + Double(index) * 60),
                    value: value
                )
            }
        )
    }

    private var history: HealthHistory {
        HealthHistory(
            window: .sixHours,
            cpu: [series(host: "Media", values: [0.2, 0.95]), series(host: "Docker", values: [0.1, 0.3])],
            memory: [series(host: "Media", values: [0.5, 0.62])],
            disk: [series(host: "Monitoring", values: [0.4, 0.44])],
            load: [series(host: "Media", values: [1.0, 1.5])]
        )
    }

    @Test("lists every host that reported anything, from any query")
    func unionsHosts() {
        #expect(history.hosts == ["Docker", "Media", "Monitoring"])
    }

    @Test("builds the current rows from the last point of each line")
    func derivesCurrentHosts() {
        let hosts = history.currentHosts

        #expect(hosts.map(\.host) == ["Docker", "Media", "Monitoring"])
        // The tile and the chart beside it are the same fetch, so they cannot
        // disagree about what the current number is.
        #expect(hosts[1].cpuUsedFraction == 0.95)
        #expect(hosts[1].memoryUsedFraction == 0.62)
        #expect(hosts[1].load1 == 1.5)
        // Absent, not zero.
        #expect(hosts[1].rootDiskUsedFraction == nil)
        #expect(hosts[0].memoryUsedFraction == nil)
    }

    @Test("names the worst host for a status strip")
    func findsPeak() {
        let peak = history.peak(.cpu)

        #expect(peak?.host == "Media")
        #expect(peak?.value == 0.95)
    }

    @Test("colours a host by the worst thing it is doing")
    func derivesSeverity() {
        let hosts = history.currentHosts

        // 95% CPU is critical even though this host's memory is fine.
        #expect(hosts[1].severity == .critical)
        #expect(hosts[0].severity == .nominal)
    }

    @Test("thresholds follow the dashboard ladder")
    func thresholdLadder() {
        #expect(MetricKind.memory.severity(for: 0.5) == .nominal)
        #expect(MetricKind.memory.severity(for: 0.85) == .warning)
        #expect(MetricKind.memory.severity(for: 0.95) == .critical)
        #expect(MetricKind.load.severity(for: 1) == .nominal)
        #expect(MetricKind.load.severity(for: 9) == .critical)
    }

    @Test("formats fractions as percentages and load as a number")
    func formatsReadings() {
        #expect(MetricKind.cpu.format(0.951) == "95%")
        #expect(MetricKind.load.format(1.5) == "1.50")
    }

    @Test("a host with no numbers is not reporting")
    func detectsSilentHost() {
        #expect(HostHealth(host: "Ghost").isReporting == false)
        #expect(HostHealth(host: "Media", load1: 0.2).isReporting)
    }
}

@Suite("Health snapshot availability")
struct HealthAvailabilityTests {
    @Test("availability is nil when nothing is monitored")
    func emptyIsNotPerfect() {
        #expect(HealthSnapshot().availability == nil)
    }

    @Test("counts the share of endpoints passing")
    func countsAvailability() {
        let snapshot = HealthSnapshot(services: [
            ServiceHealth(name: "plex", host: "Media", isUp: true),
            ServiceHealth(name: "sonarr", host: "Media", isUp: false),
            ServiceHealth(name: "grafana", host: "Monitoring", isUp: true),
            ServiceHealth(name: "loki", host: "Monitoring", isUp: true),
        ])

        #expect(snapshot.availability == 0.75)
        #expect(snapshot.downServices.map(\.name) == ["sonarr"])
    }

    @Test("maps Gatus labels onto the Host Label, never instance")
    func mapsGatusGroups() {
        let services = HealthMonitor.services(from: [
            PrometheusSample(labels: ["name": "plex", "group": "Media"], value: 1),
            PrometheusSample(labels: ["name": "sonarr", "group": "Media"], value: 0),
            // No `name` label: not a service, so not a row.
            PrometheusSample(labels: ["group": "Media"], value: 1),
        ])

        #expect(services.map(\.name) == ["plex", "sonarr"])
        #expect(services[0].host == "Media")
        #expect(services[1].isUp == false)
    }
}

@Suite("Log levels")
struct LogLevelTests {
    @Test(
        "reads a level out of the line, because Docker logs carry no level label",
        arguments: [
            ("level=error msg=\"boom\"", LogLevel.error),
            ("ERROR failed to connect", LogLevel.error),
            ("panic: runtime error", LogLevel.error),
            ("WARN disk nearly full", LogLevel.warning),
            ("level=warn retrying", LogLevel.warning),
            ("level=debug cache hit", LogLevel.debug),
            ("GET /api/v1/status 200", LogLevel.info),
        ]
    )
    func inferLevel(line: String, expected: LogLevel) {
        #expect(LogLevel(line: line) == expected)
    }

    @Test("only the head of the line is scanned")
    func ignoresLateMentions() {
        // A line whose payload merely contains the word "error" — a URL, a
        // field name, a body — is not an error line.
        let line = String(repeating: "x", count: 120) + " error"

        #expect(LogLevel(line: line) == .info)
    }

    @Test("only errors and warnings are worth colouring")
    func notableLevels() {
        #expect(LogLevel.error.isNotable)
        #expect(LogLevel.warning.isNotable)
        #expect(LogLevel.info.isNotable == false)
        #expect(LogLevel.debug.isNotable == false)
    }
}
