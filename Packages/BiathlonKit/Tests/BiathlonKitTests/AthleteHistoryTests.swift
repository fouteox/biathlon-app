import Foundation
import Testing

@testable import BiathlonKit

struct AthleteHistoryTests {
    /// A minimal `AllResults` row, whose `Season` reads "25/26".
    static func result(_ raceID: String, season: String, level: String = "WC") -> String {
        #"{"RaceId":"\#(raceID)","SeasonId":null,"Season":"\#(season)","Level":"\#(level)","Place":"Oslo","Rank":"2."}"#
    }

    static func history(_ rows: [String], now: String) throws -> AthleteHistory {
        AthleteHistory(results: try decode("[\(rows.joined(separator: ","))]"), now: date(now))
    }

    @Test func resultsKnowTheirSeason() throws {
        let row: AthleteResult = try decode(Self.result("BT2526SWRLCP09SWSP", season: "25/26"))
        #expect(row.seasonID == SeasonID(rawValue: "2526"))
        let unlabeled: AthleteResult = try decode(#"{"RaceId":"BT2526SWRLCP09SWSP","Season":null}"#)
        #expect(unlabeled.seasonID == nil)
    }

    /// The seasons with World Cup circuit results, newest first, and the current one even without results.
    @Test func seasonsStartWithTheCurrentOne() throws {
        let history = try Self.history(
            [
                Self.result("BT2425SWRLCP01SWSP", season: "24/25"),
                Self.result("SB2627SIBUL1MUSWSF", season: "26/27", level: "SBSIBUL1"),
                Self.result("BT2526SWRLOG__SWIN", season: "25/26", level: "OWG"),
                Self.result("BT2526SWRLCP09SWSP", season: "25/26"),
            ], now: "2026-10-26T12:00:00Z")
        #expect(history.seasons.map(\.rawValue) == ["2627", "2526", "2425"])
        #expect(history.results.map(\.raceID) == ["BT2425SWRLCP01SWSP", "BT2526SWRLOG__SWIN", "BT2526SWRLCP09SWSP"])
        #expect(
            history.results(in: SeasonID(rawValue: "2526")).map(\.raceID) == [
                "BT2526SWRLOG__SWIN", "BT2526SWRLCP09SWSP",
            ])
        #expect(history.results(in: SeasonID(rawValue: "2627")).isEmpty)
    }

    /// Before the athlete's first race of the season, the profile opens on their last season, as the standings do.
    @Test func opensOnTheLastSeasonWithResults() throws {
        let preseason = try Self.history(
            [Self.result("BT2526SWRLCP09SWSP", season: "25/26")], now: "2026-10-26T12:00:00Z")
        #expect(preseason.initialSeason.rawValue == "2526")
        let inSeason = try Self.history(
            [Self.result("BT2627SWRLCP01SWSP", season: "26/27"), Self.result("BT2526SWRLCP09SWSP", season: "25/26")],
            now: "2026-12-01T12:00:00Z")
        #expect(inSeason.initialSeason.rawValue == "2627")
        let newcomer = try Self.history([], now: "2026-10-26T12:00:00Z")
        #expect(newcomer.seasons.map(\.rawValue) == ["2627"])
        #expect(newcomer.initialSeason.rawValue == "2627")
    }

    /// The athlete's row in the overall standings of their category and of the season.
    @Test func worldCupStandingOfAnAthlete() async throws {
        let client = stubClient([
            "CupResults?CupId=BT2526SWRLCP__SWTS": #"""
            {"Rows":[{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"1000"},
             {"Rank":"6","IBUId":"BTFRA20910199601","Name":"SIMON Julia","Nat":"FRA","Score":"827"}]}
            """#
        ])
        let season = SeasonID(rawValue: "2526")
        let standing = try await client.worldCupStanding(of: "BTFRA20910199601", category: .women, season: season)
        #expect(standing?.rank == "6")
        #expect(standing?.score == "827")
        #expect(try await client.worldCupStanding(of: "BTFRA9", category: .women, season: season) == nil)
    }
}
