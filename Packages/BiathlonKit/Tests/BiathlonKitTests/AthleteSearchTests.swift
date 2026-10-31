import Foundation
import Testing

@testable import BiathlonKit

struct AthleteSearchTests {
    private static func person(_ id: String, _ family: String, _ given: String, _ functions: String = "Athlete")
        -> String
    {
        #"{"IBUId":"\#(id)","FamilyName":"\#(family)","GivenName":"\#(given)","NAT":"FRA","Functions":"\#(functions)"}"#
    }

    private static func answer(_ people: String...) -> String {
        #"{"RequestId":"","Athletes":[\#(people.joined(separator: ","))]}"#
    }

    @Test func oneWordStartsEitherName() {
        #expect(
            AthleteSearch.queries(for: "  Quentin ") == [
                .init(familyName: "quentin"), .init(givenName: "quentin"),
            ])
    }

    @Test func severalWordsAreEitherNameOrBothNamesSplitAnywhereInEitherOrder() {
        #expect(
            AthleteSearch.queries(for: "Quentin Fillon Maillet") == [
                .init(familyName: "quentin fillon maillet"),
                .init(givenName: "quentin fillon maillet"),
                .init(familyName: "fillon maillet", givenName: "quentin"),
                .init(familyName: "quentin", givenName: "fillon maillet"),
                .init(familyName: "maillet", givenName: "quentin fillon"),
                .init(familyName: "quentin fillon", givenName: "maillet"),
            ])
    }

    @Test func blankTextSearchesNothing() async throws {
        #expect(AthleteSearch.queries(for: " \n").isEmpty)
        #expect(try await stubClient([:]).searchAthletes(" ").isEmpty)
    }

    /// Family names first, each athlete once, without the officials the search also finds.
    @Test func mergesTheAnswersInOrder() async throws {
        let client = stubClient([
            "Athletes?FamilyName=simon": Self.answer(
                Self.person("BTFRA20910199601", "SIMON", "Julia"),
                Self.person("SWE-16-565EV", "SIMONSSON", "Emil", "Official"),
                Self.person("BTHUN22309197401", "SIMON", "Agnes", "Not active")),
            "Athletes?GivenName=simon": Self.answer(
                Self.person("BTFRA11003199901", "DESTHIEUX", "Simon"),
                Self.person("BTFRA20910199601", "SIMON", "Julia")),
        ])

        let found = try await client.searchAthletes("Simon")

        #expect(found.map(\.id) == ["BTFRA20910199601", "BTHUN22309197401", "BTFRA11003199901"])
        #expect(found.first?.name == "Julia SIMON")
        #expect(found.first?.nation == "FRA")
    }

    /// Active, former and deceased athletes, even when also officials; officials alone left out.
    @Test(arguments: [
        ("Athlete", true), ("Not active", true), ("Deceased", true), ("Athlete, Official", true),
        ("Official", false),
    ])
    func keepsAthletesOnly(functions: String, isAthlete: Bool) throws {
        let match: AthleteMatch = try decode(Self.person("BTNOR11807199801", "BAKKEN", "Sivert Guttorm", functions))
        #expect(match.isAthlete == isAthlete)
    }

    @Test func findsAnAthleteByBothNames() async throws {
        let julia = Self.person("BTFRA20910199601", "SIMON", "Julia")
        let client = stubClient([
            "Athletes?FamilyName=julia%20simon": Self.answer(),
            "Athletes?GivenName=julia%20simon": Self.answer(),
            "Athletes?FamilyName=simon&GivenName=julia": Self.answer(julia),
            "Athletes?FamilyName=julia&GivenName=simon": Self.answer(),
        ])

        #expect(try await client.searchAthletes("Julia Simon").map(\.id) == ["BTFRA20910199601"])
    }
}
