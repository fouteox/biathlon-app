import Foundation
import Testing

@testable import BiathlonKit

struct StandingsTests {
    static let empty = #"{"CupId":"X","Rows":[]}"#
    static let one = #"""
        {"CupId":"X","AsOf":"after 1 of 26 races","Rows":[{"Rank":"1","IBUId":"A","Name":"A","Nat":"FRA","Score":"90"}]}
        """#

    @Test func cupID() {
        #expect(
            Cup.worldCupID(SeasonID(rawValue: "2627"), category: .men, discipline: .total) == "BT2627SWRLCP__SMTS")
        #expect(
            Cup.worldCupID(SeasonID(rawValue: "2627"), category: .women, discipline: .nations) == "BT2627SWRLCP__SWNC")
    }

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
}
