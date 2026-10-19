import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/race-status.json` is shared with the server (`server/test`), so
/// the app and the alerts agree on which races are cancelled or finished.
struct RaceStatusTests {
    struct Case: Decodable, CustomTestStringConvertible {
        let name: String
        let status: String
        let race: Competition
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "race-status", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder.ibu.decode([Case].self, from: Data(contentsOf: url))
    }()

    @Test(arguments: cases)
    func sharedStatus(_ example: Case) {
        #expect(example.race.state.rawValue == example.status)
    }

    @Test func liveWinsOverSchedule() throws {
        let live: Competition = try decode(race("R1", start: "2026-11-26T15:15:00Z", isLive: true))
        #expect(live.state == .live)
    }

    @Test func category() throws {
        let women: Competition = try decode(race("R1", start: "2026-11-26T15:15:00Z", category: "SW"))
        #expect(women.category == .women)
    }
}
