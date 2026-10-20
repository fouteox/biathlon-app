import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/race-status.json` is shared with the server (`server/test`), so
/// the app, the alerts and the Live Activities agree on a race's status.
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

    /// Real IDs: `BT2526SWRLCP03SMMS` (Le Grand-Bornand), `BT2526SWRLOG__SMIN` (Antholz-Anterselva Olympics).
    @Test(arguments: [("BT2526SWRLCP03SMMS", "BT2526SWRLCP03"), ("BT2526SWRLOG__SMIN", "BT2526SWRLOG__")])
    func eventID(raceID: String, eventID: String) throws {
        let race: Competition = try decode(race(raceID, start: "2026-02-10T12:30:00Z"))
        #expect(race.eventID == eventID)
    }

    @Test func category() throws {
        let women: Competition = try decode(race("R1", start: "2026-11-26T15:15:00Z", category: "SW"))
        #expect(women.category == .women)
    }
}
