import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/race-kinds.json` lists every `catId` + `DisciplineId` pair of the World Cup,
/// Olympic and World Championships races of seasons 2024-25 to 2026-27. It is shared with
/// the server (`server/test`), whose alerts name a race by the same localization key.
struct RaceKindTests {
    @Test func knowsEveryRaceKind() throws {
        let url = try #require(
            Bundle.module.url(forResource: "race-kinds", withExtension: "json", subdirectory: "Fixtures"))
        let codes = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        #expect(RaceKind.allCases.map(\.rawValue).sorted() == codes)
    }

    /// Real IDs: `BT2526SWRLCP03SMMS` (Le Grand-Bornand), `BT2526SWRLOG__MXRL` (Antholz-Anterselva
    /// Olympics) and `BT1314SWRLCP08SMSPS` (a Kontiolahti sprint, with a fifth character).
    @Test(arguments: [
        ("BT2526SWRLCP03SMMS", RaceKind.menMassStart), ("BT2526SWRLOG__MXRL", .mixedRelay),
        ("BT1314SWRLCP08SMSPS", .menSprint),
    ])
    func readsTheRaceID(raceID: String, kind: RaceKind) throws {
        let race: Competition = try decode(race(raceID, start: "2026-02-10T12:30:00Z"))
        #expect(race.kind == kind)
        #expect(kind.localizationKey == "race.\(kind.rawValue)")
    }

    @Test func leavesAnUnknownKindOut() throws {
        let race: Competition = try decode(race("BT2526SWRLCP03SMXX", start: "2026-02-10T12:30:00Z"))
        #expect(race.kind == nil)
    }

    /// An athlete's history, from `AllResults`: only the races of the World Cup circuit get a name.
    @Test func athleteHistory() throws {
        let worldCup: AthleteResult = try decode(
            #"{"RaceId":"BT2526SWRLCP09SMPU","Season":"25/26","Comp":"PU","Level":"WC","Place":"Oslo","Rank":"1."}"#)
        let summer: AthleteResult = try decode(
            #"{"RaceId":"SB2627SIBUL1MUSMSF","Season":"26/27","Comp":"SF","Level":"SBSIBUL1","Place":"Munich"}"#)
        #expect(worldCup.isWorldCupCircuit)
        #expect(worldCup.kind == .menPursuit)
        #expect(!summer.isWorldCupCircuit)
    }
}
