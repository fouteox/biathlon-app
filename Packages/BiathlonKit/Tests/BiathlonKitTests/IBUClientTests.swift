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

    /// An athlete's result names its race by ID alone: the race is found among its event's.
    @Test func findsARaceByItsID() async throws {
        let client = stubClient([
            "Competitions?EventId=BT2526SWRLCP09": """
            [\(race("BT2526SWRLCP09SWSP", start: "2026-03-19T15:15:00Z", category: "SW", status: 11)),
             \(race("BT2526SWRLCP09SMSP", start: "2026-03-20T15:15:00Z", status: 11))]
            """
        ])
        let found = try await client.race(id: "BT2526SWRLCP09SMSP")
        #expect(found.id == "BT2526SWRLCP09SMSP")
        let error = await #expect(throws: IBUError.self) { try await client.race(id: "BT2526SWRLCP09SMPU") }
        guard case .unknownRace("BT2526SWRLCP09SMPU")? = error else {
            Issue.record("Expected an unknown race, got \(String(describing: error))")
            return
        }
    }
}
