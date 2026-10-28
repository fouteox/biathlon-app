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

    @Test func isEmptyWithoutAthletesOrNations() {
        #expect(FavoriteSet(athleteIDs: [], nations: []).isEmpty)
        #expect(!FavoriteSet(athleteIDs: [], nations: ["NOR"]).isEmpty)
        #expect(!FavoriteSet(athleteIDs: ["BTFRA1"], nations: []).isEmpty)
    }

    @Test func aRelayTeamIsAFavoriteThroughItsLegs() throws {
        let results: RaceResults = try decode(
            #"""
            {"IsResult":true,"Results":[
            {"IsTeam":true,"Name":"FRANCE","Nat":"FRA","TeamId":"FRA1"},
            {"IBUId":"BTFRA1","Name":"A","Nat":"FRA","TeamId":"FRA1","Leg":1},
            {"IsTeam":true,"Name":"SWEDEN","Nat":"SWE","TeamId":"SWE1"},
            {"IBUId":"BTSWE1","Name":"C","Nat":"SWE","TeamId":"SWE1","Leg":1},
            {"IsTeam":true,"Name":"NORWAY","Nat":"NOR","TeamId":"NOR1"}]}
            """#)
        #expect(results.featuredStandings(top: 0, favorites: favorites).map(\.name) == ["FRANCE", "NORWAY"])
    }

    @Test func anIndividualRaceKeepsItsFavoriteRows() throws {
        let results: RaceResults = try decode(
            #"""
            {"IsResult":true,"Results":[
            {"IBUId":"BTFRA1","Name":"A","Nat":"FRA"},
            {"IBUId":"BTFRA2","Name":"B","Nat":"FRA"}]}
            """#)
        #expect(results.featuredStandings(top: 0, favorites: favorites).map(\.name) == ["A"])
    }

    /// The top rows, then the favorites ranked below them, each row once.
    @Test func featuresTheTopThenTheFavoritesBelowIt() throws {
        let results: RaceResults = try decode(
            #"""
            {"IsResult":true,"Results":[
            {"IBUId":"BTSWE1","Name":"A","Nat":"SWE"},
            {"IBUId":"BTFRA1","Name":"B","Nat":"FRA"},
            {"IBUId":"BTGER1","Name":"C","Nat":"GER"},
            {"IBUId":"BTITA1","Name":"D","Nat":"ITA"},
            {"IBUId":"BTNOR1","Name":"E","Nat":"NOR"}]}
            """#)
        #expect(results.featuredStandings(top: 3, favorites: favorites).map(\.name) == ["A", "B", "C", "E"])
    }
}
