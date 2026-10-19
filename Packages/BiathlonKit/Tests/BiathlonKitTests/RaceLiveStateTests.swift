import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/live-activity.json` is shared with the server (`server/test`): the server
/// builds the same state from the same results and sends it as the Live Activity's
/// `content-state`, which ActivityKit decodes with a plain `JSONDecoder`.
struct RaceLiveStateTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let results: RaceResults
        let state: RaceLiveState?
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "live-activity", withExtension: "json", subdirectory: "Fixtures")!
        let objects = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        return objects.map { object in
            let json = { (key: String) in
                try! JSONSerialization.data(withJSONObject: object[key]!, options: .fragmentsAllowed)
            }
            return Case(
                name: object["name"] as! String,
                results: try! JSONDecoder.ibu.decode(RaceResults.self, from: json("results")),
                // As ActivityKit reads it: default decoding strategies.
                state: try! JSONDecoder().decode(RaceLiveState?.self, from: json("state")))
        }
    }()

    @Test(arguments: cases)
    func sharedState(_ example: Case) {
        #expect(RaceLiveState(example.results) == example.state)
    }

    @Test func roundTripsThroughDefaultCoding() throws {
        let state = try #require(Self.cases.compactMap(\.state).first)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RaceLiveState.self, from: data) == state)
    }

    @Test func onlyLiveAndUpcomingRacesCanBeFollowed() {
        #expect(Competition.State.allCases.filter(\.canBeFollowedLive) == [.scheduled, .live])
    }
}
