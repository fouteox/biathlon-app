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
        #expect(!standings.isFallback)
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

    /// Until every one of the four standings has rows, all four come from the previous season: around
    /// the opening races, a women's standing without rows yet must not show next to the men's new one.
    @Test func previousSeasonForAllFourWhileAnyIsEmpty() async throws {
        var routes = [
            "CupResults?CupId=BT2627SWRLCP__SMTS": Self.rows(
                #"{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"60"}"#),
            "CupResults?CupId=BT2627SWRLCP__SWTS": Self.rows(""),
            "CupResults?CupId=BT2627SWRLCP__SMNC": Self.rows(#"{"Rank":"1","Name":"France","Nat":"FRA"}"#),
            "CupResults?CupId=BT2627SWRLCP__SWNC": Self.rows(""),
        ]
        for (route, body) in Self.rows2526 { routes[route] = body }
        let standings = try await stubClient(routes).favoriteStandings(now: date("2026-11-28T12:00:00Z"))
        #expect(standings.season.rawValue == "2526")
        #expect(standings.requestedSeason.rawValue == "2627")
        #expect(standings.isFallback)
        #expect(standings.standing(ofAthlete: "BTFRA1")?.score == "1000")
    }

    static let rows2526 = [
        "CupResults?CupId=BT2526SWRLCP__SMTS": rows(
            #"{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"1000"}"#),
        "CupResults?CupId=BT2526SWRLCP__SWTS": rows(
            #"{"Rank":"1","IBUId":"BTNOR2","Name":"B","Nat":"NOR","Score":"900"}"#),
        "CupResults?CupId=BT2526SWRLCP__SMNC": rows(#"{"Rank":"1","Name":"France","Nat":"FRA"}"#),
        "CupResults?CupId=BT2526SWRLCP__SWNC": rows(#"{"Rank":"1","Name":"Norway","Nat":"NOR"}"#),
    ]
}
