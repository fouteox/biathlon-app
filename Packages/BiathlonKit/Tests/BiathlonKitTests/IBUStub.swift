import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An `IBUClient` answering from canned JSON, keyed by `Path?query` with the
/// query items sorted as the client sends them (`Events?Level=1&SeasonId=2627`).
func stubClient(_ routes: [String: String], status: Int = 200) -> IBUClient {
    IBUClient(baseURL: IBUClient.ibuBaseURL, transport: stubTransport(routes, status: status))
}

func stubTransport(_ routes: [String: String], status: Int = 200) -> HTTPTransport {
    { request in
        let url = try #require(request.url)
        let key = routeKey(url)
        guard let body = routes[key] else { throw StubError.unknownRoute(key) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

/// `Path?query`, as `stubClient` routes are keyed.
func routeKey(_ url: URL) -> String {
    url.lastPathComponent + "?" + (url.query ?? "")
}

/// Holds each arriving request until `count` of them have arrived: a client that sends
/// them one after another waits until its test's time limit cancels it.
actor Rendezvous {
    private let count: Int
    private var arrived = 0

    init(count: Int) {
        self.count = count
    }

    func arrive() async throws {
        arrived += 1
        while arrived < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// An `IBUClient` answering from `routes`, whose requests to each of `together` meet
/// in their own `Rendezvous` before being answered.
func rendezvousClient(_ routes: [String: String], together: [[String]]) -> IBUClient {
    let stub = stubTransport(routes)
    let meetings = together.map { keys in (keys: Set(keys), rendezvous: Rendezvous(count: keys.count)) }
    return IBUClient(baseURL: IBUClient.ibuBaseURL) { request in
        let url = try #require(request.url)
        if let meeting = meetings.first(where: { $0.keys.contains(routeKey(url)) }) {
            try await meeting.rendezvous.arrive()
        }
        return try await stub(request)
    }
}

enum StubError: Error {
    case unknownRoute(String)
}

func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try JSONDecoder.ibu.decode(T.self, from: Data(json.utf8))
}

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

/// A minimal `Competitions` row.
func race(
    _ id: String, start: String, category: String = "SM", status: Int = 1, scheduleStatus: String = "SCHEDULED",
    isLive: Bool = false
) -> String {
    """
    {"RaceId":"\(id)","catId":"\(category)","ShortDescription":"\(id)","StartTime":"\(start)",\
    "StatusId":\(status),"ScheduleStatus":"\(scheduleStatus)","IsLive":\(isLive)}
    """
}

/// A minimal `Events` row.
func event(_ id: String, start: String, end: String) -> String {
    #"{"EventId":"\#(id)","ShortDescription":"\#(id)","StartDate":"\#(start)","EndDate":"\#(end)","Nat":"FIN"}"#
}
