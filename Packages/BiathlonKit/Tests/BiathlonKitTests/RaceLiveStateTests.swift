import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/live-activity.json` is shared with the server (`server/test`): the server
/// builds each state from its results and sends it as the Live Activity's
/// `content-state`, which ActivityKit decodes with a plain `JSONDecoder`, with its
/// `relevance-score`, which the app's local updates give as well.
struct RaceLiveStateTests {
    struct Case: Decodable, CustomTestStringConvertible {
        let name: String
        let state: RaceLiveState?
        let relevanceScore: Double?
        var testDescription: String { name }
    }

    /// As ActivityKit reads a `content-state`: default decoding strategies.
    static func cases() throws -> [Case] {
        let url = try #require(
            Bundle.module.url(forResource: "live-activity", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test(arguments: try cases())
    func decodesTheServersState(_ example: Case) {
        #expect(example.state?.relevanceScore == example.relevanceScore)
    }

    @Test func roundTripsThroughDefaultCoding() throws {
        let state = try #require(Self.cases().compactMap(\.state).first)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RaceLiveState.self, from: data) == state)
    }

    @Test func activitiesOfLaterRacesStartShortlyBeforeTheStart() {
        let start = date("2026-11-26T15:15:00Z")
        #expect(
            RaceLiveState.activityStart(raceStart: start, now: date("2026-11-24T09:00:00Z"))
                == date("2026-11-26T14:45:00Z"))
        #expect(RaceLiveState.activityStart(raceStart: start, now: date("2026-11-26T15:00:00Z")) == nil)
        #expect(RaceLiveState.activityStart(raceStart: start, now: date("2026-11-26T15:30:00Z")) == nil)
    }
}
