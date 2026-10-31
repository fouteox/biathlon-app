import Foundation
import Testing

@testable import BiathlonKit

/// What Siri says of a race's results.
struct SpokenResultsTests {
    private static func row(
        _ name: String, family: String? = nil, given: String? = nil, nation: String = "NOR", rank: String? = nil,
        irm: String? = nil, isTeam: Bool = false
    ) throws -> ResultRow {
        var fields = [#""Name":"\#(name)""#, #""Nat":"\#(nation)""#, #""IsTeam":\#(isTeam)"#]
        if let family { fields.append(#""FamilyName":"\#(family)""#) }
        if let given { fields.append(#""GivenName":"\#(given)""#) }
        if let rank { fields.append(#""Rank":"\#(rank)""#) }
        if let irm { fields.append(#""IRM":"\#(irm)""#) }
        return try decode("{\(fields.joined(separator: ","))}")
    }

    @Test func athletesGivenNameFirstWithoutCapitals() throws {
        let row = try Self.row(
            "FILLON MAILLET Quentin", family: "FILLON MAILLET", given: "Quentin", nation: "FRA")
        #expect(row.spokenName(locale: Locale(identifier: "fr_FR")) == "Quentin Fillon Maillet")
    }

    @Test func teamsByTheirNation() throws {
        let team = try Self.row("NORWAY", family: "NORWAY", given: "", isTeam: true)
        #expect(team.spokenName(locale: Locale(identifier: "de_DE")) == "Norwegen")
    }

    @Test func theFullNameWithoutItsParts() throws {
        #expect(try Self.row("BOTN Johan-Olav").spokenName() == "BOTN Johan-Olav")
    }

    /// The first three who finished, from the standings: teams only for a relay.
    @Test func podiumOfTheFinishers() throws {
        let results: RaceResults = try decode(
            """
            {"IsResult":true,"Results":[
            {"Name":"A","Rank":"1"},{"Name":"B","Rank":"2"},{"Name":"C","IRM":"DSQ"},
            {"Name":"D","Rank":"3"},{"Name":"E","Rank":"4"}]}
            """)
        #expect(results.podium.map(\.name) == ["A", "B", "D"])
    }

    @Test func noPodiumOnAStartList() throws {
        let startList: RaceResults = try decode(#"{"IsStartList":true,"Results":[{"Name":"A"}]}"#)
        #expect(startList.podium.isEmpty)
    }
}
