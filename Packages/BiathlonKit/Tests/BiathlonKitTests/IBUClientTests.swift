import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct IBUClientTests {
    @Test func buildsSortedQuery() async throws {
        let client = IBUClient(baseURL: IBUClient.ibuBaseURL) { url in
            #expect(url.absoluteString == IBUClient.ibuBaseURL.absoluteString + "Events?Level=1&SeasonId=2627")
            return (Data("[]".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await client.events(season: SeasonID(rawValue: "2627")).isEmpty)
    }

    @Test func httpErrorCarriesTheStatus() async {
        let client = stubClient(["Results?RaceId=R1": "{}"], status: 503)
        await #expect(throws: IBUError.self) {
            try await client.results(raceID: "R1")
        }
        do {
            _ = try await client.results(raceID: "R1")
        } catch let IBUError.http(code) {
            #expect(code == 503)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func decodingErrorNamesTheEndpoint() async {
        let client = stubClient(["Results?RaceId=R1": "not json"])
        do {
            _ = try await client.results(raceID: "R1")
            Issue.record("Expected a decoding error")
        } catch let IBUError.decoding(path, _) {
            #expect(path == "Results")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
