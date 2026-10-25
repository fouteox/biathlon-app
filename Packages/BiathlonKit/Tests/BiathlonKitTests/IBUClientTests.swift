import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct IBUClientTests {
    @Test func buildsSortedQuery() async throws {
        let client = IBUClient(baseURL: IBUClient.ibuBaseURL) { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == IBUClient.ibuBaseURL.absoluteString + "Events?Level=1&SeasonId=2627")
            return (Data("[]".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await client.events(season: SeasonID(rawValue: "2627")).isEmpty)
    }

    /// The app builds its base URL as the app does: the server URL plus `ibu/`.
    @Test(arguments: ["https://example.workers.dev", "https://example.workers.dev/"])
    func usesTheServerCacheWithTheSamePaths(server: String) async throws {
        let baseURL = URL(string: server)!.appending(path: "ibu/")
        let client = IBUClient(baseURL: baseURL) { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://example.workers.dev/ibu/Events?Level=1&SeasonId=2627")
            return (Data("[]".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await client.events(season: SeasonID(rawValue: "2627")).isEmpty)
    }

    @Test func httpErrorCarriesTheStatus() async {
        let client = stubClient(["Results?RaceId=R1": "{}"], status: 503)
        let error = await #expect(throws: IBUError.self) { try await client.results(raceID: "R1") }
        guard case .http(let status)? = error else {
            Issue.record("Expected an HTTP error, got \(String(describing: error))")
            return
        }
        #expect(status == 503)
    }

    @Test func decodingErrorNamesTheEndpoint() async {
        let client = stubClient(["Results?RaceId=R1": "not json"])
        let error = await #expect(throws: IBUError.self) { try await client.results(raceID: "R1") }
        guard case .decoding(let path, _)? = error else {
            Issue.record("Expected a decoding error, got \(String(describing: error))")
            return
        }
        #expect(path == "Results")
    }
}
