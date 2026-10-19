import Testing

@testable import BiathlonKit

struct FavoriteSetTests {
    let favorites = FavoriteSet(athleteIDs: ["BTFRA1"], nations: ["NOR"])

    @Test func matchesAthletesAndNations() throws {
        let athlete: ResultRow = try decode(#"{"IBUId":"BTFRA1","Name":"A","Nat":"FRA"}"#)
        let teammate: ResultRow = try decode(#"{"IBUId":"BTFRA2","Name":"B","Nat":"FRA"}"#)
        let team: ResultRow = try decode(#"{"IsTeam":true,"Name":"NORWAY","Nat":"NOR","TeamId":"NOR1"}"#)
        #expect(favorites.contains(athlete))
        #expect(!favorites.contains(teammate))
        #expect(favorites.contains(team))
    }

    @Test func aNationKeyNeverMatchesAnAthleteID() throws {
        let row: ResultRow = try decode(#"{"IBUId":"NOR","Name":"Odd","Nat":"SWE"}"#)
        #expect(!favorites.contains(row))
    }
}
