import Foundation
import HomelabCore

/// The macOS half of `GitHubTransport`: renders a `GitHubRequest` back into the
/// `gh` argv the client used to build directly, so the menu bar app keeps the
/// property that made it worth writing — it holds no credential of its own, and
/// `gh auth login` is the whole of its credential management.
///
/// Every shape `GitHubRequest` can take maps onto `gh api`, including GraphQL,
/// which is why the iOS app could be added without the macOS app changing
/// behaviour. See ADR-0004.
public struct GhCommandTransport: GitHubTransport {
    private let runner: any CommandRunner

    public init(runner: any CommandRunner = GitHubCommandLineRunner()) {
        self.runner = runner
    }

    public func send(_ request: GitHubRequest) async throws(GitHubFailure) -> Data {
        do {
            return try await runner.run(Self.arguments(for: request))
        } catch {
            throw Self.failure(from: error)
        }
    }

    static func arguments(for request: GitHubRequest) -> [String] {
        switch request.body {
        case .rest(let method, let path, let fields):
            var arguments = ["api"]
            if method != .get {
                arguments += ["--method", method.rawValue]
            }
            arguments.append(path)
            // Sorted so the argv is deterministic and testable; `gh` does not
            // care about the order of `-f` pairs.
            for key in fields.keys.sorted() {
                arguments += ["-f", "\(key)=\(fields[key]!)"]
            }
            return arguments

        case .graphQL(let query, let variables):
            var arguments = ["api", "graphql", "-f", "query=\(query)"]
            for key in variables.keys.sorted() {
                arguments += ["-f", "\(key)=\(variables[key]!)"]
            }
            return arguments
        }
    }

    /// `gh`'s vocabulary, translated once, here — so nothing above this file
    /// has to know that a command line tool was ever involved.
    static func failure(from failure: CommandFailure) -> GitHubFailure {
        switch failure {
        case .executableNotFound:
            return .transportUnavailable("`gh` not found — install the GitHub CLI")
        case .terminated(let exitCode, let standardError):
            // `gh` exits 4 when the stored credentials are missing or expired.
            if exitCode == 4 || standardError.localizedCaseInsensitiveContains("gh auth login") {
                return .notAuthenticated
            }
            return .requestFailed(
                status: Int(exitCode),
                message: standardError.isEmpty ? "`gh` failed" : standardError
            )
        }
    }
}
