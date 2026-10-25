import BiathlonKit
import Foundation
import Testing

/// The notification server, answering each `METHOD /path` with canned responses in turn,
/// the last one again once the others are used, and keeping every request it receives.
/// It hands out challenges and accepts attested keys unless a test answers otherwise.
actor ServerStub {
    nonisolated struct Response {
        let status: Int
        let body: String

        init(_ status: Int, _ body: String = "") {
            self.status = status
            self.body = body
        }
    }

    private nonisolated static let baseURL = URL(string: "https://example.workers.dev")!
    private nonisolated static let attestation: [String: [Response]] = [
        "POST /v1/app-attest/challenges": [Response(201, #"{"challenge":"c1"}"#)],
        "POST /v1/app-attest/keys": [Response(204)],
    ]

    private var requests: [URLRequest] = []
    private var responses: [String: [Response]]

    init(_ responses: [String: [Response]]) {
        self.responses = Self.attestation.merging(responses) { $1 }
    }

    nonisolated var client: ServerClient {
        ServerClient(baseURL: Self.baseURL) { request in try await self.respond(to: request) }
    }

    /// The `METHOD /path` of every request received, in order.
    var routes: [String] {
        requests.map { Self.route(of: $0) }
    }

    func requests(to route: String) -> [URLRequest] {
        requests.filter { Self.route(of: $0) == route }
    }

    private func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let route = Self.route(of: request)
        let queued = try #require(responses[route], "No response for \(route)")
        if queued.count > 1 { responses[route]?.removeFirst() }
        let response = try #require(queued.first)
        let http = try #require(
            HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil))
        return (Data(response.body.utf8), http)
    }

    private nonisolated static func route(of request: URLRequest) -> String {
        "\(request.httpMethod ?? "GET") \(request.url?.path(percentEncoded: true) ?? "")"
    }
}
