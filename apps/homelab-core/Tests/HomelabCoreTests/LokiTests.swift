import Foundation
import Testing
@testable import HomelabCore

/// `.serialized` because `RoutingURLProtocol` records the last URL in static
/// storage, and two tests reading it at once would race.
@Suite("Loki queries", .serialized)
struct LokiQueryTests {
    @Test("escapes a regex matcher so the server does not read `+` as a space")
    func encodesPlusInSelectors() async throws {
        // The bug this exists for: `URLComponents.queryItems` leaves `+` alone,
        // and Go's `url.ParseQuery` — which is how Loki reads the request —
        // turns a bare `+` into a space. The unfiltered selector is
        // `{container=~".+"}`, so Loki was being asked for `{container=~". "}`
        // and answering, correctly, with nothing at all.
        let selector = LokiClient.selector(host: nil, container: nil)
        #expect(selector == "{container=~\".+\"}")

        let client = LokiClient(
            baseURL: URL(string: "http://loki.test:3100")!,
            session: RoutingURLProtocol.session()
        )
        _ = try await client.queryRange(selector, start: Date(timeIntervalSince1970: 0))

        let url = try #require(RoutingURLProtocol.lastQueryRangeURL)
        #expect(url.query?.contains("%2B") == true)
        #expect(goStyleQuery(url)["query"] == selector)
    }

    @Test("a selector with no regex in it survives the same trip")
    func encodesOrdinarySelectors() async throws {
        let selector = LokiClient.selector(host: "Bumblebee", container: "traefik")
        let client = LokiClient(
            baseURL: URL(string: "http://loki.test:3100")!,
            session: RoutingURLProtocol.session()
        )
        _ = try await client.queryRange(selector, start: Date(timeIntervalSince1970: 0))

        let url = try #require(RoutingURLProtocol.lastQueryRangeURL)
        #expect(goStyleQuery(url)["query"] == "{host=\"Bumblebee\", container=\"traefik\"}")
    }

    /// Decodes a query string the way Go's `net/url` does, which is the only
    /// reading of it that matters: `+` is a space, everything else is
    /// percent-decoded.
    private func goStyleQuery(_ url: URL) -> [String: String] {
        (url.query ?? "").split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first, parts.count == 2 else { return }
            let value = parts[1].replacingOccurrences(of: "+", with: " ")
            result[String(name)] = value.removingPercentEncoding ?? value
        }
    }
}

@Suite("Loki decoding")
struct LokiDecodingTests {
    @Test("reads a query_range response")
    func decodesQueryRange() throws {
        let payload = """
        {
          "status": "success",
          "data": {
            "resultType": "streams",
            "result": [
              {
                "stream": {"container": "traefik", "host": "Bumblebee"},
                "values": [["1700000001000000000", "second"], ["1700000000000000000", "first"]]
              }
            ]
          }
        }
        """

        let entries = try LokiClient.decodeEntries(from: Data(payload.utf8))

        #expect(entries.map(\.line) == ["first", "second"])
        #expect(entries.first?.container == "traefik")
        #expect(entries.first?.host == "Bumblebee")
    }

    @Test("reads a tail frame, which is not shaped like a query response")
    func decodesTailFrame() throws {
        // No `status`, no `data` — decoding this as a query response failed on
        // every frame, which is why the Live toggle never produced a line.
        let frame = """
        {
          "streams": [
            {
              "stream": {"container": "loki"},
              "values": [["1700000000000000000", "level=info msg=\\"tailing\\""]]
            }
          ],
          "dropped_entries": null
        }
        """

        let entries = try LokiClient.decodeTailEntries(from: Data(frame.utf8))

        #expect(entries.count == 1)
        #expect(entries.first?.record.message == "tailing")
    }

    @Test("reports a rejected query rather than pretending it was empty")
    func reportsRejection() {
        let payload = #"{"status":"error","error":"parse error at line 1"}"#

        #expect(throws: LokiFailure.queryRejected("parse error at line 1")) {
            try LokiClient.decodeEntries(from: Data(payload.utf8))
        }
    }
}

/// Answers Loki's endpoints by path, and remembers the last `query_range` URL
/// so a test can assert what was actually put on the wire.
final class RoutingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordedURL: URL?

    static var lastQueryRangeURL: URL? { lock.withLock { recordedURL } }

    static func session() -> URLSession {
        lock.withLock { recordedURL = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let body: String

        if url.path.contains("query_range") {
            Self.lock.withLock { Self.recordedURL = url }
            body = #"{"status":"success","data":{"resultType":"streams","result":[]}}"#
        } else {
            body = #"{"status":"success","data":[]}"#
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
