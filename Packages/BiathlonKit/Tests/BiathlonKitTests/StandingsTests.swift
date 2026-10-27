import Foundation
import Testing

@testable import BiathlonKit

struct StandingsTests {
    static let empty = #"{"CupId":"X","Rows":[]}"#
    static let one = #"""
        {"CupId":"X","AsOf":"after 1 of 26 races","Rows":[{"Rank":"1","IBUId":"A","Name":"A","Nat":"FRA","Score":"90"}]}
        """#

    @Test func currentSeasonWhenItHasRows() async throws {
        let client = stubClient(["CupResults?CupId=BT2627SWRLCP__SWSP": Self.one])
        let standings = try await client.worldCupStandings(
            category: .women, discipline: .sprint, now: date("2026-12-10T12:00:00Z"))
        #expect(standings.season.rawValue == "2627")
        #expect(!standings.isFallback)
        #expect(standings.standings.rows.count == 1)
    }

    @Test func previousSeasonBeforeTheFirstRace() async throws {
        let client = stubClient([
            "CupResults?CupId=BT2627SWRLCP__SMTS": Self.empty,
            "CupResults?CupId=BT2526SWRLCP__SMTS": Self.one,
        ])
        let standings = try await client.worldCupStandings(
            category: .men, discipline: .total, now: date("2026-10-19T12:00:00Z"))
        #expect(standings.season.rawValue == "2526")
        #expect(standings.requestedSeason.rawValue == "2627")
        #expect(standings.isFallback)
    }

    /// A season picked on the standings screen shows as it is, even before its first race.
    @Test func pickedSeasonWithoutFallback() async throws {
        let client = stubClient(["CupResults?CupId=BT2627SWRLCP__SMTS": Self.empty])
        let standings = try await client.worldCupStandings(
            category: .men, discipline: .total, season: SeasonID(rawValue: "2627"))
        #expect(standings.season.rawValue == "2627")
        #expect(!standings.isFallback)
        #expect(standings.standings.rows.isEmpty)
    }

    @Test func pickedPastSeason() async throws {
        let client = stubClient(["CupResults?CupId=BT2425SWRLCP__SWPU": Self.one])
        let standings = try await client.worldCupStandings(
            category: .women, discipline: .pursuit, season: SeasonID(rawValue: "2425"))
        #expect(standings.season.rawValue == "2425")
        #expect(standings.standings.rows.count == 1)
    }

    /// A nation's screen lists its athletes in the order of the standings, without the nation's own row.
    @Test func athletesOfANation() throws {
        let cup: CupStandings = try decode(
            #"""
            {"Rows":[{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA"},{"Rank":"2","IBUId":"BTNOR1","Name":"B","Nat":"NOR"},
             {"Rank":"3","IBUId":"BTFRA2","Name":"C","Nat":"FRA"},{"Rank":"1","IBUId":"FRA","Name":"France","Nat":"FRA"}]}
            """#)
        #expect(cup.athletes(of: "FRA").map(\.athleteID) == ["BTFRA1", "BTFRA2"])
        #expect(cup.athletes(of: "SWE").isEmpty)
    }

    /// An athlete's standings are those of their gender.
    @Test(arguments: [(Gender.man, RaceCategory.men), (.woman, .women)])
    func standingsCategoryOfAGender(gender: Gender, category: RaceCategory) {
        #expect(gender.category == category)
    }
}
