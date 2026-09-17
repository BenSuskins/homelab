import Foundation
import Testing
@testable import HomelabCore

@Suite("Log line parsing")
struct LogRecordTests {
    // MARK: logfmt

    @Test("takes a logfmt line apart")
    func readsLogfmt() {
        let record = LogRecord(
            line: #"ts=2026-09-17T09:41:02.118Z level=warn msg="retrying" component=loki attempt=3"#
        )

        #expect(record.shape == .logfmt)
        #expect(record.level == .warning)
        #expect(record.declaresLevel)
        #expect(record.message == "retrying")
        #expect(record.fields.map(\.key) == ["component", "attempt"])
        #expect(record["attempt"] == "3")
        #expect(record.timestamp != nil)
    }

    @Test("keeps escaped quotes inside a logfmt value")
    func readsEscapedValues() {
        let record = LogRecord(
            line: #"level=error msg="cannot open \"/data/db\"" caller=store.go:88"#
        )

        #expect(record.level == .error)
        #expect(record.message == #"cannot open "/data/db""#)
        #expect(record["caller"] == "store.go:88")
    }

    @Test("does not mistake prose that mentions key=value for logfmt")
    func refusesProse() {
        // Two pairs, but the line does not open with one — so it is a sentence
        // with some equals signs in it, and reformatting it would lose the
        // sentence.
        let line = "Started sync with mode=fast and target=nas after 3 retries"
        let record = LogRecord(line: line)

        #expect(record.shape == .plain)
        #expect(record.message == line)
    }

    // MARK: JSON

    @Test("takes a JSON line apart")
    func readsJSON() {
        let record = LogRecord(line: """
        {"level":"error","msg":"backend down","time":"2026-09-17T09:41:02Z",\
        "status":502,"retry":true,"router":"api@docker"}
        """)

        #expect(record.shape == .json)
        #expect(record.level == .error)
        #expect(record.declaresLevel)
        #expect(record.message == "backend down")
        #expect(record["status"] == "502")
        // A boolean written as `true` has to read as `true`, not as `1`.
        #expect(record["retry"] == "true")
        #expect(record["router"] == "api@docker")
        #expect(record.timestamp != nil)
    }

    @Test("leaves a line that merely starts with a brace alone")
    func refusesNonJSON() {
        let record = LogRecord(line: "{not json after all")
        #expect(record.shape == .plain)
    }

    // MARK: Plain

    @Test("lifts a bracketed level and a leading timestamp off a plain line")
    func readsPlainWithBrackets() {
        let record = LogRecord(line: "2026/09/17 09:41:02.118 [error] AdGuard could not bind :53")

        #expect(record.shape == .plain)
        #expect(record.level == .error)
        #expect(record.declaresLevel)
        #expect(record.timestamp != nil)
        #expect(record.message == "AdGuard could not bind :53")
    }

    @Test("falls back to guessing when the line declares nothing")
    func guessesLevel() {
        let record = LogRecord(line: "Plex Media Server starting up")

        #expect(record.shape == .plain)
        #expect(record.level == .info)
        // The distinction the detail screen shows, and the one the filter
        // needs: this level is ours, not the line's.
        #expect(!record.declaresLevel)
        #expect(record.message == "Plex Media Server starting up")
    }

    @Test("keeps an unparseable line intact rather than emptying it")
    func keepsUnstructuredLines() {
        let line = "|====> 87% <====|"
        #expect(LogRecord(line: line).message == line)
    }

    // MARK: Levels

    @Test(
        "maps the words containers actually write to the four levels",
        arguments: [
            ("FATAL", LogLevel.error),
            ("eror", LogLevel.error),
            ("WRN", LogLevel.warning),
            ("notice", LogLevel.info),
            ("trace", LogLevel.debug),
        ]
    )
    func readsLevelTokens(token: String, expected: LogLevel) {
        #expect(LogLevel(token: token) == expected)
    }

    @Test("has no opinion about a word that is not a level")
    func rejectsNonLevels() {
        #expect(LogLevel(token: "starting") == nil)
    }

    // MARK: Entry

    @Test("prefers the container's own timestamp over the ingest one")
    func prefersWrittenTimestamp() {
        let ingested = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = LokiLogEntry(
            timestamp: ingested,
            labels: ["container": "loki"],
            line: "ts=2026-09-17T09:41:02.118Z level=info msg=ready"
        )

        #expect(entry.writtenAt != ingested)
        #expect(entry.writtenAt == entry.record.timestamp)
        #expect(entry.level == .info)
    }
}
