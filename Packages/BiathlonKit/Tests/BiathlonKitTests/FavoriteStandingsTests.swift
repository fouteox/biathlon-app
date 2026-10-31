import Testing

@testable import BiathlonKit

struct FavoriteStandingsTests {
    static func rows(_ rows: String) -> String { #"{"Rows":[\#(rows)]}"# }

    let client = stubClient([
        "CupResults?CupId=BT2627SWRLCP__SMTS": rows(
            #"{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"300"}"#),
        "CupResults?CupId=BT2627SWRLCP__SWTS": rows(
            #"{"Rank":"4","IBUId":"BTNOR2","Name":"B","Nat":"NOR","Score":"150"}"#),
        "CupResults?CupId=BT2627SWRLCP__SMNC": rows(#"{"Rank":"2","IBUId":"FRA","Name":"France","Nat":"FRA"}"#),
        "CupResults?CupId=BT2627SWRLCP__SWNC": rows(
            #"{"Rank":"1","Name":"Norway","Nat":"NOR"},{"Rank":"3","Name":"France","Nat":"FRA"}"#),
    ])

    @Test func findsAnAthleteInEitherCategory() async throws {
        let standings = try await client.favoriteStandings(now: date("2026-12-10T12:00:00Z"))
        #expect(standings.season.rawValue == "2627")
        #expect(standings.standing(ofAthlete: "BTFRA1")?.rank == "1")
        #expect(standings.standing(ofAthlete: "BTNOR2")?.score == "150")
        #expect(standings.standing(ofAthlete: "BTGER1") == nil)
    }

    /// A nation by its code, which the Nations Cup rows carry as `Nat` or as `IBUId`, men's first.
    @Test func listsANationsRanksMenFirst() async throws {
        let standings = try await client.favoriteStandings(now: date("2026-12-10T12:00:00Z"))
        #expect(
            standings.standings(ofNation: "FRA").map { "\($0.category.rawValue) \($0.row.rank ?? "")" } == [
                "SM 2", "SW 3",
            ])
        #expect(standings.standings(ofNation: "NOR").map(\.category) == [.women])
        #expect(standings.standings(ofNation: "GER").isEmpty)
    }
}
