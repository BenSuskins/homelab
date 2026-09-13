import Foundation

/// Talks to `api.github.com` directly with a bearer token. This is the iOS side
/// of the seam — iOS cannot spawn `gh`, which is the whole reason the seam
/// exists (see ADR-0004).
public struct URLSessionTransport: GitHubTransport {
    private let session: URLSession
    private let tokens: any TokenProviding
    private let apiRoot: URL

    public init(
        tokens: any TokenProviding,
        session: URLSession = .shared,
        apiRoot: URL = URL(string: "https://api.github.com")!
    ) {
        self.tokens = tokens
        self.session = session
        self.apiRoot = apiRoot
    }

    public func send(_ request: GitHubRequest) async throws(GitHubFailure) -> Data {
        guard let token = await tokens.token() else { throw .notAuthenticated }

        let urlRequest: URLRequest
        do {
            urlRequest = try build(request, token: token)
        } catch let failure as GitHubFailure {
            throw failure
        } catch {
            throw .malformedResponse(String(describing: error))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw .transportUnavailable((error as NSError).localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .malformedResponse("Response was not HTTP")
        }

        switch http.statusCode {
        case 200..<300:
            // GraphQL reports its own errors with a 200 and an `errors` array,
            // so a success status is not on its own a success.
            try Self.rejectGraphQLErrors(in: data, for: request)
            return data
        case 401:
            throw .notAuthenticated
        default:
            throw .requestFailed(
                status: http.statusCode,
                message: Self.message(from: data, status: http.statusCode)
            )
        }
    }

    private func build(_ request: GitHubRequest, token: String) throws -> URLRequest {
        var urlRequest: URLRequest

        switch request.body {
        case .rest(let method, let path, let fields):
            // Built by string rather than `appendingPathComponent`, which
            // percent-escapes the `?` and turns a query into part of the path.
            let root = apiRoot.absoluteString.hasSuffix("/")
                ? String(apiRoot.absoluteString.dropLast())
                : apiRoot.absoluteString
            guard let url = URL(string: "\(root)/\(path)") else {
                throw GitHubFailure.malformedResponse("Bad path: \(path)")
            }
            urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = method.rawValue
            if !fields.isEmpty {
                urlRequest.httpBody = try JSONEncoder().encode(fields)
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

        case .graphQL(let query, let variables):
            urlRequest = URLRequest(url: apiRoot.appendingPathComponent("graphql"))
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = try JSONEncoder().encode(
                GraphQLEnvelope(query: query, variables: variables)
            )
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return urlRequest
    }

    private struct GraphQLEnvelope: Encodable {
        let query: String
        let variables: [String: String]
    }

    private struct ErrorPayload: Decodable {
        struct Entry: Decodable { let message: String }
        let message: String?
        let errors: [Entry]?
    }

    static func rejectGraphQLErrors(in data: Data, for request: GitHubRequest) throws(GitHubFailure) {
        guard case .graphQL = request.body else { return }
        guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
              let errors = payload.errors, !errors.isEmpty
        else { return }

        throw .requestFailed(
            status: 200,
            message: errors.map(\.message).joined(separator: "; ")
        )
    }

    static func message(from data: Data, status: Int) -> String {
        guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) else {
            return "HTTP \(status)"
        }
        if let errors = payload.errors, !errors.isEmpty {
            return errors.map(\.message).joined(separator: "; ")
        }
        return payload.message ?? "HTTP \(status)"
    }
}
