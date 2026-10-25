import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The notification server, answering each `METHOD /path` with canned responses in turn,
/// the last one again once the others are used, and keeping every request it receives.
actor ServerStub {
    struct Response {
        let status: Int
        let body: String

        init(_ status: Int, _ body: String = "") {
            self.status = status
            self.body = body
        }
    }

    static let baseURL = URL(string: "https://example.workers.dev")!

    private(set) var requests: [URLRequest] = []
    private var responses: [String: [Response]]

    init(_ responses: [String: [Response]]) {
        self.responses = responses
    }

    nonisolated var client: ServerClient {
        ServerClient(baseURL: Self.baseURL) { request in try await self.respond(to: request) }
    }

    private func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let route = "\(request.httpMethod ?? "GET") \(url.path(percentEncoded: true))"
        guard let queued = responses[route], let response = queued.first else { throw StubError.unknownRoute(route) }
        if queued.count > 1 { responses[route]?.removeFirst() }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        return (Data(response.body.utf8), http)
    }
}
