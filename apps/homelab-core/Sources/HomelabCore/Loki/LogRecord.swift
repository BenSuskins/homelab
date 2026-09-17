import Foundation

/// One key and value read out of a structured log line.
public struct LogField: Sendable, Equatable, Identifiable {
    public let key: String
    public let value: String

    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// How a line was written. Alloy's `loki.source.docker` ships container stdout
/// verbatim, so this is read off the line itself rather than off a label — and
/// the three shapes below are what the homelab's containers actually emit.
public enum LogShape: String, Sendable, Equatable, Codable, CaseIterable {
    /// One JSON object per line. Traefik, and most Go services with a JSON
    /// encoder configured.
    case json
    /// `key=value` pairs. Alloy, Loki, Grafana, logrus' default.
    case logfmt
    /// Whatever the container felt like. Shown verbatim.
    case plain

    public var label: String {
        switch self {
        case .json: "JSON"
        case .logfmt: "logfmt"
        case .plain: "Plain"
        }
    }
}

/// A log line, taken apart.
///
/// The point is the list: a row that shows `msg` and a couple of fields is
/// readable at a glance, where 400 characters of `ts=… level=… caller=… msg=…`
/// is not. Nothing is thrown away — the detail sheet shows every field and the
/// raw line underneath them — so a parse that guesses wrong costs presentation,
/// never information.
public struct LogRecord: Sendable, Equatable {
    public let shape: LogShape
    public let level: LogLevel
    /// Whether the line said what level it was rather than us inferring it from
    /// the words in it. A guess is good enough to tint a row; only a declared
    /// level is good enough to filter on without quietly hiding lines.
    public let declaresLevel: Bool
    /// The timestamp the container wrote, which is not always the one Loki
    /// stamped the entry with.
    public let timestamp: Date?
    /// The human-readable part, or the whole line when there is no structure.
    public let message: String
    /// Everything else, in the order it was written for logfmt and sorted for
    /// JSON, which has no order worth preserving.
    public let fields: [LogField]

    public init(
        shape: LogShape,
        level: LogLevel,
        declaresLevel: Bool,
        timestamp: Date?,
        message: String,
        fields: [LogField]
    ) {
        self.shape = shape
        self.level = level
        self.declaresLevel = declaresLevel
        self.timestamp = timestamp
        self.message = message
        self.fields = fields
    }

    public var isStructured: Bool { shape != .plain }

    public subscript(key: String) -> String? {
        fields.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    // MARK: Parsing

    /// Keys promoted out of `fields` and onto the record, so they are not shown
    /// twice. Matched case-insensitively — `Level` and `LEVEL` both occur.
    private static let levelKeys = ["level", "lvl", "loglevel", "severity", "severitytext"]
    private static let messageKeys = ["msg", "message", "event", "error", "err", "detail"]
    private static let timestampKeys = ["ts", "t", "time", "timestamp", "@timestamp", "date"]

    public init(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if let record = Self.parseJSON(trimmed) {
            self = record
        } else if let record = Self.parseLogfmt(trimmed) {
            self = record
        } else {
            self = Self.parsePlain(trimmed)
        }
    }

    // MARK: JSON

    private static func parseJSON(_ line: String) -> LogRecord? {
        guard line.hasPrefix("{"), line.hasSuffix("}"),
              let data = line.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              !object.isEmpty
        else { return nil }

        // Sorted rather than written order: `JSONDecoder` does not preserve the
        // document's order, so alphabetical is at least the same every time.
        let pairs = object
            .map { LogField(key: $0.key, value: $0.value.text) }
            .sorted { $0.key < $1.key }

        return make(shape: .json, pairs: pairs, fallbackMessage: line)
    }

    // MARK: logfmt

    private static func parseLogfmt(_ line: String) -> LogRecord? {
        let pairs = pairs(in: line)

        // Two pairs, and the line has to *open* with one. A prose line that
        // happens to contain `foo=bar` twice is not logfmt, and treating it as
        // such would drop the prose.
        guard pairs.count >= 2,
              let first = line.split(separator: " ", maxSplits: 1).first,
              let equals = first.firstIndex(of: "="),
              isPlausibleKey(first[first.startIndex..<equals])
        else { return nil }

        return make(shape: .logfmt, pairs: pairs, fallbackMessage: line)
    }

    /// What a field name can look like. Without this, an ASCII progress bar
    /// (`|====> 87% <====|`) parses as two pairs keyed `|` and `<`, and a line
    /// that is not structured at all gets rendered as though it were.
    private static func isPlausibleKey(_ key: some StringProtocol) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" || first == "@" else {
            return false
        }
        return key.count <= 48 && key.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" || $0 == "@"
        }
    }

    /// A logfmt scanner. Written by hand rather than as a regular expression
    /// because the values are quoted with escapes, which a regex handles badly
    /// and which every one of these lines relies on.
    static func pairs(in line: String) -> [LogField] {
        var fields: [LogField] = []
        var index = line.startIndex

        func skipSpaces() {
            while index < line.endIndex, line[index] == " " {
                index = line.index(after: index)
            }
        }

        while index < line.endIndex {
            skipSpaces()
            guard index < line.endIndex else { break }

            let keyStart = index
            while index < line.endIndex, line[index] != "=", line[index] != " " {
                index = line.index(after: index)
            }

            guard index < line.endIndex, line[index] == "=",
                  isPlausibleKey(line[keyStart..<index]) else {
                // A bare word between pairs, or something that only looks like
                // one. Skip it: the raw line is kept, so nothing is lost by not
                // inventing a key for it.
                while index < line.endIndex, line[index] != " " {
                    index = line.index(after: index)
                }
                continue
            }

            let key = String(line[keyStart..<index])
            index = line.index(after: index)

            var value = ""
            if index < line.endIndex, line[index] == "\"" {
                index = line.index(after: index)
                var isEscaped = false
                while index < line.endIndex {
                    let character = line[index]
                    index = line.index(after: index)
                    if isEscaped {
                        switch character {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        case "r": value.append("\r")
                        default: value.append(character)
                        }
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        break
                    } else {
                        value.append(character)
                    }
                }
            } else {
                let valueStart = index
                while index < line.endIndex, line[index] != " " {
                    index = line.index(after: index)
                }
                value = String(line[valueStart..<index])
            }

            if !key.isEmpty {
                fields.append(LogField(key: key, value: value))
            }
        }

        return fields
    }

    // MARK: Plain

    /// No structure to read, so the most that can be done is lift a leading
    /// timestamp and a bracketed level out of the front of the line — which
    /// between them cover AdGuard, qBittorrent, Plex and the *arr stack.
    private static func parsePlain(_ line: String) -> LogRecord {
        var remainder = Substring(line)
        let timestamp = takeLeadingTimestamp(&remainder)
        let declared = takeBracketedLevel(&remainder)
        let message = remainder.trimmingCharacters(in: .whitespaces)

        return LogRecord(
            shape: .plain,
            level: declared ?? LogLevel(line: line),
            declaresLevel: declared != nil,
            timestamp: timestamp,
            message: message.isEmpty ? line : message,
            fields: []
        )
    }

    /// Consumes `2026-09-17T10:00:00.123Z` or `2026/09/17 10:00:00.123` from
    /// the front, and leaves the line alone if it finds neither.
    private static func takeLeadingTimestamp(_ line: inout Substring) -> Date? {
        let firstEnd = line.firstIndex(of: " ") ?? line.endIndex
        var secondEnd = line.endIndex
        if firstEnd < line.endIndex {
            let rest = line[line.index(after: firstEnd)...]
            secondEnd = rest.firstIndex(of: " ") ?? line.endIndex
        }

        // Longest first, so `2026/09/17 10:00:00.123` wins over the date alone.
        for end in [secondEnd, firstEnd] where end > line.startIndex {
            guard let date = Timestamps.parse(String(line[line.startIndex..<end])) else { continue }
            line = line[end...]
            return date
        }
        return nil
    }

    /// Consumes a leading `[info]`, `[ERROR]`, `INFO:` and so on.
    private static func takeBracketedLevel(_ line: inout Substring) -> LogLevel? {
        let head = line.drop { $0 == " " }

        if head.hasPrefix("["), let close = head.firstIndex(of: "]") {
            let token = head[head.index(after: head.startIndex)..<close]
            if let level = LogLevel(token: String(token)) {
                line = head[head.index(after: close)...]
                return level
            }
        }

        let word = head.prefix { $0 != " " }
        if word.hasSuffix(":"), let level = LogLevel(token: String(word.dropLast())) {
            line = head.dropFirst(word.count)
            return level
        }

        return nil
    }

    // MARK: Assembly

    /// Turns a bag of pairs into a record, promoting level, message and
    /// timestamp out of it. Shared by both structured shapes because the rules
    /// for which key means what are the same either way.
    private static func make(
        shape: LogShape,
        pairs: [LogField],
        fallbackMessage: String
    ) -> LogRecord {
        var remaining = pairs

        func take(_ keys: [String]) -> String? {
            for key in keys {
                guard let position = remaining.firstIndex(where: {
                    $0.key.lowercased() == key
                }) else { continue }
                return remaining.remove(at: position).value
            }
            return nil
        }

        let levelToken = take(levelKeys)
        let message = take(messageKeys)
        let timestamp = take(timestampKeys)
        let declared = levelToken.flatMap(LogLevel.init(token:))

        return LogRecord(
            shape: shape,
            level: declared ?? LogLevel(line: message ?? fallbackMessage),
            declaresLevel: declared != nil,
            timestamp: timestamp.flatMap(Timestamps.parse),
            // A structured line with no message key keeps the whole line as its
            // summary. Duplicated in the detail sheet's raw section, which is
            // collapsed — better than a row with nothing on it.
            message: message ?? fallbackMessage,
            fields: remaining
        )
    }
}

/// The timestamp formats that turn up inside log lines.
///
/// Held as statics because a formatter is expensive to build and these are hit
/// once per line, five hundred lines at a time. `nonisolated(unsafe)` is the
/// honest label for that: Foundation's formatters are safe to *use* from
/// several threads, they are only unsafe to reconfigure, and nothing here
/// touches one after it is built.
enum Timestamps {
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601WholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Slash-separated dates with a space, which AdGuard and several of the
    /// *arr containers use and which `ISO8601DateFormatter` will not touch.
    nonisolated(unsafe) private static let slashed: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
        return formatter
    }()

    nonisolated(unsafe) private static let slashedWholeSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"[] "))
        guard !trimmed.isEmpty else { return nil }

        if let date = iso8601.date(from: trimmed) { return date }
        if let date = iso8601WholeSeconds.date(from: trimmed) { return date }
        if let date = slashed.date(from: trimmed) { return date }
        if let date = slashedWholeSeconds.date(from: trimmed) { return date }

        // Unix time, which logfmt emitters write as seconds and JSON emitters
        // sometimes write as milliseconds. Bounded so a status code or a byte
        // count never reads as a date.
        if let seconds = Double(trimmed) {
            if (1_000_000_000...4_000_000_000).contains(seconds) {
                return Date(timeIntervalSince1970: seconds)
            }
            if (1_000_000_000_000...4_000_000_000_000).contains(seconds) {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
        }

        return nil
    }
}

/// Just enough of a JSON value to render one as text. `JSONSerialization` would
/// do the decoding, but it bridges booleans to `NSNumber` and there is then no
/// clean way to tell `true` from `1` — which matters, because a field shown as
/// `1` when the container wrote `true` is a lie in a log viewer.
enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Bool first: `Int` would happily decode `true` on some platforms.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var text: String {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .number(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        case .null: "null"
        case .array(let values): "[" + values.map(\.text).joined(separator: ", ") + "]"
        case .object(let values):
            "{" + values.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.text)" }
                .joined(separator: ", ") + "}"
        }
    }
}
