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
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/query"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "query", value: query)]

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

        let payload: QueryPayload
        do {
            payload = try JSONDecoder().decode(QueryPayload.self, from: data)
        } catch {
            throw .malformedResponse(String(describing: error))
        }

        guard payload.status == "success" else {
            throw .queryRejected(payload.error ?? "Prometheus reported \(payload.status)")
        }

        return payload.data?.result.map {
            PrometheusSample(labels: $0.metric, value: $0.sampleValue)
        } ?? []
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
    /// a heterogeneous array, so it needs unkeyed decoding by hand.
    private struct Series: Decodable {
        let metric: [String: String]
        let sampleValue: Double

        enum CodingKeys: String, CodingKey {
            case metric
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            metric = try container.decodeIfPresent([String: String].self, forKey: .metric) ?? [:]

            var pair = try container.nestedUnkeyedContainer(forKey: .value)
            _ = try pair.decode(Double.self)
            let raw = try pair.decode(String.self)
            // NaN arrives as the literal "NaN"; treat it as absent data rather
            // than failing the whole query.
            sampleValue = Double(raw) ?? .nan
        }
    }
}
