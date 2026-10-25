import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An `IBUClient` answering from canned JSON, keyed by `Path?query` with the
/// query items sorted as the client sends them (`Events?Level=1&SeasonId=2627`).
func stubClient(_ routes: [String: String], status: Int = 200) -> IBUClient {
    IBUClient(baseURL: IBUClient.ibuBaseURL) { request in
        let url = try #require(request.url)
        let key = url.lastPathComponent + "?" + (url.query ?? "")
        guard let body = routes[key] else { throw StubError.unknownRoute(key) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
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
