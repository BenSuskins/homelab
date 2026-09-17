import Foundation

public enum PrometheusFailure: Error, Equatable, Sendable {
    /// The tailnet is not up, or Prometheus is down. Distinct from every other
    /// case because it is the expected state off the tailnet, not a fault.
    case unreachable(String)
    case queryRejected(String)
    case malformedResponse(String)

    public var displayMessage: String {
        switch self {
        case .unreachable:
            "Not connected to the tailnet"
        case .queryRejected(let detail):
            detail.isEmpty ? "Prometheus rejected the query" : detail
        case .malformedResponse:
            "Unexpected response from Prometheus"
        }
    }
}

/// One point of an instant query result: the metric's labels and its value.
public struct PrometheusSample: Sendable, Equatable {
    public let labels: [String: String]
    public let value: Double

    public init(labels: [String: String], value: Double) {
        self.labels = labels
        self.value = value
    }

    public subscript(label: String) -> String? { labels[label] }
}

/// Reads Prometheus directly on the host port over the tailnet.
///
/// Not through `prometheus.suskins.co.uk`, which is `secured: true` and so sits
/// behind Authelia — a browser session flow that a native client has no good
/// way to hold. The Subnet Router advertises the LAN, the host port is
/// unauthenticated, and the tailnet is the perimeter. Gatus would otherwise be
/// the obvious source for service health, but its own `security.oidc` block
/// puts its API behind the same problem, so its metrics are read from here
/// instead.
public struct PrometheusClient: Sendable {
    public static let defaultBaseURL = URL(string: "http://192.168.0.203:9090")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = PrometheusClient.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? {
            let configuration = URLSessionConfiguration.ephemeral
            // Off the tailnet this should fail fast and say so, not spin.
            configuration.timeoutIntervalForRequest = 8
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }()
    }

    public func instantQuery(_ query: String) async throws(PrometheusFailure) -> [PrometheusSample] {
        let data = try await get(
            path: "api/v1/query",
            items: [URLQueryItem(name: "query", value: query)]
        )
        let payload = try decode(data)

        return payload.data?.result.compactMap { series -> PrometheusSample? in
            guard let value = series.sampleValue else { return nil }
            return PrometheusSample(labels: series.metric, value: value)
        } ?? []
    }

    /// The history behind an instant query. Same labels, a line instead of a
    /// number — this is what every chart in the app is drawn from.
    ///
    /// `start` and `end` are sent as Unix seconds because Prometheus accepts
    /// RFC 3339 only with a timezone Foundation's default formatter does not
    /// always spell the way it wants; seconds are unambiguous.
    public func rangeQuery(
        _ query: String,
        start: Date,
        end: Date = Date(),
        step: TimeInterval
    ) async throws(PrometheusFailure) -> [MetricSeries] {
        let data = try await get(
            path: "api/v1/query_range",
            items: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "start", value: Self.seconds(start)),
                URLQueryItem(name: "end", value: Self.seconds(end)),
                URLQueryItem(name: "step", value: String(Int(step.rounded()))),
            ]
        )
        let payload = try decode(data)

        return payload.data?.result.map {
            MetricSeries(labels: $0.metric, points: $0.seriesPoints)
        } ?? []
    }

    /// `rangeQuery` over a `MetricWindow`, which is how every caller in the app
    /// asks — the window owns its own step so no screen has to pick one.
    public func rangeQuery(
        _ query: String,
        window: MetricWindow,
        now: Date = Date()
    ) async throws(PrometheusFailure) -> [MetricSeries] {
        try await rangeQuery(
            query,
            start: now.addingTimeInterval(-window.duration),
            end: now,
            step: window.step
        )
    }

    // MARK: Plumbing

    private func get(
        path: String,
        items: [URLQueryItem]
    ) async throws(PrometheusFailure) -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        // `percentEncodedQueryItems`, not `queryItems`: the latter leaves `+`
        // alone and Prometheus then reads it as a space, which would silently
        // break the first query anyone writes with a `.+` matcher in it. See
        // `QueryEncoding`, and the logs screen that this had already broken.
        components?.percentEncodedQueryItems = QueryEncoding.encoded(items)

        guard let url = components?.url else {
            throw .malformedResponse("Could not build query URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw .unreachable((error as NSError).localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .queryRejected("HTTP \(http.statusCode)")
        }

        return data
    }

    private func decode(_ data: Data) throws(PrometheusFailure) -> QueryPayload {
        let payload: QueryPayload
        do {
            payload = try JSONDecoder().decode(QueryPayload.self, from: data)
        } catch {
            throw .malformedResponse(String(describing: error))
        }

        guard payload.status == "success" else {
            throw .queryRejected(payload.error ?? "Prometheus reported \(payload.status)")
        }

        return payload
    }

    private static func seconds(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded()))
    }

    // MARK: Wire shapes

    private struct QueryPayload: Decodable {
        let status: String
        let error: String?
        let data: ResultData?
    }

    private struct ResultData: Decodable {
        let result: [Series]
    }

    /// Prometheus encodes a sample as `[<unix seconds>, "<value as string>"]` —
    /// a heterogeneous array, so it needs unkeyed decoding by hand. A vector
    /// carries one under `value`; a matrix carries many under `values`. One
    /// type decodes both so the two query paths share a payload.
    private struct Series: Decodable {
        let metric: [String: String]
        /// Nil when the sample is NaN, which Prometheus sends as the literal
        /// "NaN" and which means "not reporting", not "zero".
        let sampleValue: Double?
        let seriesPoints: [MetricPoint]

        enum CodingKeys: String, CodingKey {
            case metric
            case value
            case values
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            metric = try container.decodeIfPresent([String: String].self, forKey: .metric) ?? [:]

            if container.contains(.value) {
                var pair = try container.nestedUnkeyedContainer(forKey: .value)
                sampleValue = try Self.decodePoint(&pair).map(\.value)
            } else {
                sampleValue = nil
            }

            if container.contains(.values) {
                var rows = try container.nestedUnkeyedContainer(forKey: .values)
                var points: [MetricPoint] = []
                while !rows.isAtEnd {
                    var pair = try rows.nestedUnkeyedContainer()
                    // A NaN in the middle of a line is a gap. Dropping the
                    // point leaves the chart's own interpolation to show it,
                    // rather than a spike to zero that reads as a real reading.
                    if let point = try Self.decodePoint(&pair) { points.append(point) }
                }
                seriesPoints = points
            } else {
                seriesPoints = []
            }
        }

        private static func decodePoint(
            _ pair: inout UnkeyedDecodingContainer
        ) throws -> MetricPoint? {
            let timestamp = try pair.decode(Double.self)
            let raw = try pair.decode(String.self)
            guard let value = Double(raw), value.isFinite else { return nil }
            return MetricPoint(date: Date(timeIntervalSince1970: timestamp), value: value)
        }
    }
}
