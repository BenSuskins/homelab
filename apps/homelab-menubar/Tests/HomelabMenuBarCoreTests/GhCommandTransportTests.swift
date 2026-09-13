import Foundation
import HomelabCore
import Testing
@testable import HomelabMenuBarCore

@Suite("GhCommandTransport")
struct GhCommandTransportTests {
    @Test("a read becomes a bare `gh api <path>` with no method flag")
    func rendersRead() {
        let arguments = GhCommandTransport.arguments(
            for: .get("repos/BenSuskins/homelab/actions/runs?per_page=1")
        )

        #expect(arguments == ["api", "repos/BenSuskins/homelab/actions/runs?per_page=1"])
    }

    @Test("a write carries its method and its fields")
    func rendersWrite() {
        let arguments = GhCommandTransport.arguments(
            for: .post("repos/x/y/actions/workflows/clean.yml/dispatches", fields: ["ref": "main"])
        )

        #expect(arguments == [
            "api", "--method", "POST",
            "repos/x/y/actions/workflows/clean.yml/dispatches",
            "-f", "ref=main",
        ])
    }

    @Test("fields are ordered so the argv is deterministic")
    func ordersFields() {
        let arguments = GhCommandTransport.arguments(
            for: .put("repos/x/y/pulls/1/merge", fields: ["z": "last", "a": "first"])
        )

        #expect(arguments.suffix(4) == ["-f", "a=first", "-f", "z=last"])
    }

    @Test("GraphQL goes through `gh api graphql` with the query as a field")
    func rendersGraphQL() {
        let arguments = GhCommandTransport.arguments(
            for: .graphQL("query($owner: String!) { x }", variables: ["owner": "BenSuskins"])
        )

        #expect(arguments == [
            "api", "graphql",
            "-f", "query=query($owner: String!) { x }",
            "-f", "owner=BenSuskins",
        ])
    }

    @Test("a missing gh reads as the transport being unavailable, not as a request failure")
    func mapsMissingExecutable() {
        let failure = GhCommandTransport.failure(from: .executableNotFound("gh"))

        guard case .transportUnavailable(let message) = failure else {
            Issue.record("Expected .transportUnavailable, got \(failure)")
            return
        }
        #expect(message.contains("gh"))
    }

    @Test("recognises an expired login rather than reporting a generic failure")
    func mapsLoggedOutState() {
        // `gh` exits 4 for this, and also says so on stderr; either is enough.
        #expect(
            GhCommandTransport.failure(from: .terminated(exitCode: 4, standardError: ""))
                == .notAuthenticated
        )
        #expect(
            GhCommandTransport.failure(
                from: .terminated(exitCode: 1, standardError: "try gh auth login")
            ) == .notAuthenticated
        )
    }

    @Test("any other non-zero exit keeps gh's own message")
    func keepsStandardError() {
        let failure = GhCommandTransport.failure(
            from: .terminated(exitCode: 1, standardError: "HTTP 404: Not Found")
        )

        #expect(failure == .requestFailed(status: 1, message: "HTTP 404: Not Found"))
    }

    @Test("drives the runner and returns its bytes untouched")
    func passesBytesThrough() async throws {
        let runner = FakeCommandRunner()
        runner.stub(containing: "graphql", json: #"{"data":{"ok":true}}"#)

        let data = try await GhCommandTransport(runner: runner).send(.graphQL("query { ok }"))

        #expect(String(decoding: data, as: UTF8.self) == #"{"data":{"ok":true}}"#)
    }
}
