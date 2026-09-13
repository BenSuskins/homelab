import Foundation
import HomelabCore
@testable import HomelabMenuBarCore

/// Stands in for `gh`. It records what was asked and replies with canned bytes,
/// so every layer above it — decoding, mapping, snapshot building — runs for
/// real in tests. Nothing is stubbed except the process boundary itself.
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    struct Invocation: Equatable {
        let arguments: [String]
    }

    private let lock = NSLock()
    private var responses: [(matches: @Sendable ([String]) -> Bool, result: Result<Data, CommandFailure>)] = []
    private var recorded: [Invocation] = []

    var invocations: [Invocation] {
        lock.withLock { recorded }
    }

    var invokedArguments: [[String]] {
        invocations.map(\.arguments)
    }

    func stub(
        containing fragment: String,
        with data: Data
    ) {
        lock.withLock {
            responses.append((
                matches: { $0.contains { $0.contains(fragment) } },
                result: .success(data)
            ))
        }
    }

    func stub(containing fragment: String, json: String) {
        stub(containing: fragment, with: Data(json.utf8))
    }

    func stub(containing fragment: String, failure: CommandFailure) {
        lock.withLock {
            responses.append((
                matches: { $0.contains { $0.contains(fragment) } },
                result: .failure(failure)
            ))
        }
    }

    func run(_ arguments: [String]) async throws(CommandFailure) -> Data {
        let result: Result<Data, CommandFailure> = lock.withLock {
            recorded.append(Invocation(arguments: arguments))
            let match = responses.first { $0.matches(arguments) }
            return match?.result ?? .success(Data("[]".utf8))
        }

        switch result {
        case .success(let data): return data
        case .failure(let failure): throw failure
        }
    }
}
