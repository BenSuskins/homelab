import Foundation

public enum LokiFailure: Error, Equatable, Sendable {
    case unreachable(String)
    case queryRejected(String)
    case malformedResponse(String)

    public var displayMessage: String {
        switch self {
        case .unreachable:
            "Not connected to the tailnet"
        case .queryRejected(let detail):
            detail.isEmpty ? "Loki rejected the query" : detail
        case .malformedResponse:
            "Unexpected response from Loki"
        }
    }
}

public struct LokiLogEntry: Sendable, Equatable, Identifiable {
    public let timestamp: Date
    public let labels: [String: String]
    public let line: String

    /// The line taken apart. Parsed once here rather than on every access,
    /// because a list of five hundred rows reads it while you scroll.
    public let record: LogRecord

    public var id: String {
        let labelText = labels.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(timestamp.timeIntervalSince1970)-\(labelText)-\(line)"
    }

    public var host: String? { labels["host"] }
    public var container: String? { labels["container"] }

    /// Read out of the line itself, because Alloy's `loki.source.docker` ships
    /// container stdout verbatim: there is no level label to read, and every
    /// container writes its own format. `LogRecord` reads a declared level
    /// where the line has one and guesses otherwise, and a guess only ever
    /// tints a row — `record.declaresLevel` is what the filter trusts.
    public var level: LogLevel { record.level }

    /// The stamp the container wrote, when it wrote one, falling back to the
    /// one Loki ingested the line with. They differ by the ingest delay, and on
    /// a bad afternoon that delay is the thing you are looking at.
    public var writtenAt: Date { record.timestamp ?? timestamp }

    public init(timestamp: Date, labels: [String: String], line: String) {
        self.timestamp = timestamp
        self.labels = labels
        self.line = line
        self.record = LogRecord(line: line)
    }
}

/// How loud a log line is. Deliberately coarse — three levels and a default —
/// because the point is to make the red ones findable while scrolling, not to
/// reproduce whatever taxonomy the container happens to use.
public enum LogLevel: String, Sendable, Equatable, CaseIterable, Codable {
    case error
    case warning
    case info
    case debug

    public init(line: String) {
        // Only the start of the line: a line that merely mentions "error" in a
        // URL or a payload is not an error line.
        let head = line.prefix(90).lowercased()

        if head.contains("error") || head.contains("fatal") || head.contains("panic")
            || head.contains(" err ") || head.contains("level=error") {
            self = .error
        } else if head.contains("warn") || head.contains("level=warn") {
            self = .warning
        } else if head.contains("debug") || head.contains("level=debug") || head.contains("trace") {
            self = .debug
        } else {
            self = .info
        }
    }

    /// A level the line actually declared — `level=warn`, `"severity":"ERROR"`,
    /// a leading `[info]`. Nil rather than a default, so a caller can tell a
    /// declared level from a guessed one.
    public init?(token: String) {
        switch token.trimmingCharacters(in: CharacterSet(charactersIn: "\"[] \t")).lowercased() {
        case "error", "err", "eror", "fatal", "critical", "crit", "panic",
             "alert", "emerg", "emergency", "severe":
            self = .error
        case "warn", "warning", "wrn":
            self = .warning
        case "info", "information", "inf", "notice", "log":
            self = .info
        case "debug", "dbg", "trace", "verbose", "fine":
            self = .debug
        default:
            return nil
        }
    }

    public var label: String {
        switch self {
        case .error: "ERR"
        case .warning: "WARN"
        case .info: "INFO"
        case .debug: "DBG"
        }
    }

    /// Loudest first, which is the order the filter chips are shown in.
    public static let bySeverity: [LogLevel] = [.error, .warning, .info, .debug]

    /// Whether the line is worth colouring at all. Info and debug are the
    /// overwhelming majority and stay in the body colour.
    public var isNotable: Bool {
        self == .error || self == .warning
    }
}

public struct LokiClient: Sendable {
    public static let defaultBaseURL = URL(string: "http://192.168.0.203:3100")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = LokiClient.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }()
    }

    public func queryRange(
        _ query: String,
        start: Date,
        end: Date = Date(),
        limit: Int = 500
    ) async throws(LokiFailure) -> [LokiLogEntry] {
        let url = try makeURL(path: "loki/api/v1/query_range", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "start", value: Self.nanoseconds(start)),
            URLQueryItem(name: "end", value: Self.nanoseconds(end)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "direction", value: "backward")
        ])
        let data = try await get(url)
        return try Self.decodeEntries(from: data)
    }

    /// The values a label takes, over the same window the entries are read for.
    ///
    /// The window is not optional in practice: Loki defaults these endpoints to
    /// the last six hours, so at a 24-hour range the pickers would otherwise
    /// omit a container that has been quiet since this morning — exactly the
    /// one you opened the app to look for.
    public func labelValues(
        _ label: String,
        start: Date? = nil,
        end: Date = Date()
    ) async throws(LokiFailure) -> [String] {
        let path = "loki/api/v1/label/\(label)/values"
        var items: [URLQueryItem] = []
        if let start {
            items = [
                URLQueryItem(name: "start", value: Self.nanoseconds(start)),
                URLQueryItem(name: "end", value: Self.nanoseconds(end)),
            ]
        }
        let data = try await get(makeURL(path: path, queryItems: items))
        return try Self.decodeLabelValues(from: data)
    }

    public func tail(
        _ query: String,
        start: Date = Date(),
        limit: Int = 100
    ) -> AsyncThrowingStream<LokiLogEntry, Error> {
        let url: URL
        do {
            url = try makeWebSocketURL(path: "loki/api/v1/tail", queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "start", value: Self.nanoseconds(start)),
                URLQueryItem(name: "limit", value: String(limit))
            ])
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: url)
            task.resume()

            Task {
                defer { task.cancel(with: .normalClosure, reason: nil) }
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data
                        switch message {
                        case .data(let value):
                            data = value
                        case .string(let value):
                            data = Data(value.utf8)
                        @unknown default:
                            continue
                        }

                        for entry in try Self.decodeTailEntries(from: data) {
                            continuation.yield(entry)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public static func selector(host: String?, container: String?) -> String {
        let values = [("host", host), ("container", container)].compactMap { name, value in
            value.map { "\(name)=\"\(escape($0))\"" }
        }
        if values.isEmpty { return "{container=~\".+\"}" }
        return "{\(values.joined(separator: ", "))}"
    }

    static func decodeEntries(from data: Data) throws(LokiFailure) -> [LokiLogEntry] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw LokiFailure.malformedResponse(String(describing: error))
        }
        guard payload.status == "success" else {
            throw LokiFailure.queryRejected(payload.error ?? "Loki reported \(payload.status)")
        }

        return entries(in: payload.data?.result ?? [])
    }

    /// `/loki/api/v1/tail` does not answer in the query envelope: a frame is
    /// `{"streams": [...], "dropped_entries": [...]}` with no `status` key at
    /// all. Decoding it as a query response therefore failed on every single
    /// frame, which is why the Live toggle lit up and then never showed a line.
    static func decodeTailEntries(from data: Data) throws(LokiFailure) -> [LokiLogEntry] {
        let payload: TailPayload
        do {
            payload = try JSONDecoder().decode(TailPayload.self, from: data)
        } catch {
            throw LokiFailure.malformedResponse(String(describing: error))
        }
        return entries(in: payload.streams ?? [])
    }

    private static func entries(in streams: [Stream]) -> [LokiLogEntry] {
        streams.flatMap { stream in
            stream.values.compactMap { value in
                guard value.count == 2,
                      let rawTimestamp = value.first,
                      let nanoseconds = Int64(rawTimestamp),
                      let line = value.last else { return nil }
                return LokiLogEntry(
                    timestamp: Date(timeIntervalSince1970: Double(nanoseconds) / 1_000_000_000),
                    labels: stream.stream,
                    line: line
                )
            }
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func decodeLabelValues(from data: Data) throws(LokiFailure) -> [String] {
        do {
            let payload = try JSONDecoder().decode(LabelPayload.self, from: data)
            guard payload.status == "success" else {
                throw LokiFailure.queryRejected("Loki reported \(payload.status)")
            }
            // Absent rather than empty is what a Loki with nothing to say
            // answers with, and it is not a malformed response.
            return (payload.data ?? []).sorted()
        } catch let failure as LokiFailure {
            throw failure
        } catch {
            throw LokiFailure.malformedResponse(String(describing: error))
        }
    }

    private func get(_ url: URL) async throws(LokiFailure) -> Data {
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

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws(LokiFailure) -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw .malformedResponse("Could not build Loki URL")
        }
        // `percentEncodedQueryItems`, not `queryItems`: the latter leaves `+`
        // alone and Loki then reads it as a space. See `QueryEncoding`.
        components.percentEncodedQueryItems = queryItems.isEmpty
            ? nil
            : QueryEncoding.encoded(queryItems)
        guard let url = components.url else {
            throw .malformedResponse("Could not build Loki URL")
        }
        return url
    }

    private func makeWebSocketURL(path: String, queryItems: [URLQueryItem]) throws(LokiFailure) -> URL {
        var url = try makeURL(path: path, queryItems: queryItems)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw .malformedResponse("Could not build Loki WebSocket URL")
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let webSocketURL = components.url else {
            throw .malformedResponse("Could not build Loki WebSocket URL")
        }
        url = webSocketURL
        return url
    }

    private static func nanoseconds(_ date: Date) -> String {
        String(Int64(date.timeIntervalSince1970 * 1_000_000_000))
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private struct Payload: Decodable {
        let status: String
        let error: String?
        let data: ResultData?
    }

    private struct ResultData: Decodable {
        let result: [Stream]
    }

    private struct TailPayload: Decodable {
        let streams: [Stream]?
    }

    private struct Stream: Decodable {
        let stream: [String: String]
        let values: [[String]]
    }

    private struct LabelPayload: Decodable {
        let status: String
        let data: [String]?
    }
}
