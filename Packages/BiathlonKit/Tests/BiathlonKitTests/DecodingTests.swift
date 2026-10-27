import Foundation
import Testing

@testable import BiathlonKit

/// Fixtures mirror the shape of real responses captured on 2026-10-19.
struct DecodingTests {
    func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder.ibu.decode(T.self, from: Data(contentsOf: url))
    }

    @Test func events() throws {
        let events: [BiathlonEvent] = try fixture("events")
        let first = try #require(events.first)
        #expect(first.id == "BT2627SWRLCP01")
        #expect(first.nation == "FIN")
        #expect(!first.isWorldChampionships)
    }

    @Test func competitionStates() throws {
        let races: [Competition] = try fixture("competitions")
        #expect(races[0].state == .scheduled)
        #expect(!races[0].isRelay)
        #expect(races[1].state == .finished)
        #expect(races[1].isRelay)
    }

    @Test func relayResults() throws {
        let results: RaceResults = try fixture("relay-results")
        #expect(results.standings.count == 1)
        let norway = try #require(results.standings.first)
        #expect(results.legs(of: norway).map(\.name) == ["ULDAL Martin"])
    }

    /// `SportEvt` of `Results?RaceId=BT2526SWRLCP01SMRL`: the event the race belongs to.
    @Test func raceResultsNameTheirEvent() throws {
        let results: RaceResults = try fixture("relay-results")
        let event = try #require(results.event)
        #expect(event.shortDescription == "Oestersund")
        #expect(event.nation == "SWE")
    }

    @Test func cupStandingsAcceptNumericScores() throws {
        let cup: CupStandings = try fixture("cup-results")
        #expect(cup.rows.count == 2)
        #expect(cup.rows[0].bibColors == ["yellow"])
        #expect(cup.rows[1].score == "968")
        #expect(cup.rows[1].rankChange == -1)
    }

    @Test func athleteDateWithoutTimeZone() throws {
        let bio: AthleteBio = try fixture("athlete")
        #expect(bio.birthdate != nil)
        #expect(bio.photoURL?.lastPathComponent == "BTFRA12906200101.png")
        #expect(!bio.isDeceased)
    }

    /// As `CISBios?IBUId=BTNOR11807199801` returns Sivert Guttorm Bakken, who died in December 2025.
    @Test func deceasedAthlete() throws {
        let bio: AthleteBio = try decode(
            #"{"IBUId":"BTNOR11807199801","FullName":"Sivert Guttorm BAKKEN","NAT":"NOR","Age":null,"Functions":"Deceased"}"#
        )
        #expect(bio.isDeceased)
        #expect(bio.age(on: date("2026-10-27T12:00:00Z")) == nil)
    }

    /// Eric Perrot, born on 29 June 2001: the age turns on the birthday, in UTC like the birthdate.
    @Test(arguments: [("2026-06-28T23:59:00Z", 24), ("2026-06-29T00:00:00Z", 25), ("2026-10-27T12:00:00Z", 25)])
    func athleteAge(on day: String, age: Int) throws {
        let bio: AthleteBio = try fixture("athlete")
        #expect(bio.age(on: date(day)) == age)
    }

    @Test func noAgeWithoutABirthdate() throws {
        let bio: AthleteBio = try decode(#"{"IBUId":"BTFRA20910199601"}"#)
        #expect(bio.age(on: date("2026-10-27T12:00:00Z")) == nil)
    }

    /// `GenderId` of `CISBios`: "M" for Sivert Guttorm Bakken, "W" for Julia Simon.
    @Test(arguments: [("M", Gender.man), ("W", Gender.woman), ("X", nil)])
    func athleteGender(id: String, gender: Gender?) throws {
        let bio: AthleteBio = try decode(#"{"IBUId":"BTFRA20910199601","GenderId":"\#(id)"}"#)
        #expect(bio.gender == gender)
    }

    /// As `CupResults?CupId=BT2526SWRLCP__SWNC` returns them: a nation's `IBUId` is its code.
    @Test func nationsStandingsRowsAreNations() throws {
        let cup: CupStandings = try decode(
            #"{"Rows":[{"Rank":"1","IBUId":"SWE","Name":"Sweden","ShortName":"Sweden","Nat":"SWE","Score":"6815"}]}"#
        )
        let row = try #require(cup.rows.first)
        #expect(row.isNation)
        #expect(row.athleteID == nil)
        #expect(row.nation == "SWE")
    }

    @Test func seasonIDs() {
        #expect(SeasonID.containing(date("2026-10-19T12:00:00Z")).rawValue == "2627")
        #expect(SeasonID.containing(date("2027-03-01T12:00:00Z")).rawValue == "2627")
        #expect(SeasonID.containing(date("2026-06-30T23:59:00Z")).rawValue == "2526")
        #expect(
            SeasonID.since(SeasonID(rawValue: "2425"), now: date("2026-10-19T12:00:00Z")).map(\.rawValue) == [
                "2627", "2526", "2425",
            ])
        // The oldest seasons biathlonresults.com lists: `Seasons` goes back to 1957-58.
        #expect(SeasonID.since(.firstWithRaces, now: date("2026-10-19T12:00:00Z")).last?.displayName == "1957-58")
        #expect(SeasonID.since(.firstWorldCup, now: date("2026-10-19T12:00:00Z")).count == 50)
        #expect(SeasonID(rawValue: "2627").previous.rawValue == "2526")
        #expect(SeasonID(rawValue: "2627").displayName == "2026-27")
        #expect(SeasonID(rawValue: "9899") < SeasonID(rawValue: "0001"))
        #expect(SeasonID(rawValue: "0001").previous.rawValue == "9900")
        #expect(SeasonID(rawValue: "9899").displayName == "1998-99")
    }

    /// Real IDs: `BT2425SWRLCP01` (Kontiolahti), `BT2425SWRLCH__` (Lenzerheide).
    @Test func worldChampionships() throws {
        let championships: BiathlonEvent = try decode(
            event("BT2425SWRLCH__", start: "2025-02-11T12:00:00Z", end: "2025-02-23T12:00:00Z"))
        #expect(championships.isWorldChampionships)
        #expect(!championships.isOlympics)
    }

    /// The Olympics are in the World Cup calendar (`Level=1`): `BT2526SWRLOG__` (Antholz-Anterselva).
    @Test func olympics() throws {
        let olympics: BiathlonEvent = try decode(
            event("BT2526SWRLOG__", start: "2026-02-06T12:00:00Z", end: "2026-02-22T12:00:00Z"))
        #expect(olympics.isOlympics)
        #expect(!olympics.isWorldChampionships)
    }
}
