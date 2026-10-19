import Foundation
import Testing
@testable import BiathlonKit

/// Les fixtures reprennent la forme des réponses réelles relevées le 19/10/2026.
struct DecodingTests {
    func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder.ibu.decode(T.self, from: Data(contentsOf: url))
    }

    @Test func events() throws {
        let events: [BiathlonEvent] = try fixture("events")
        let first = try #require(events.first)
        #expect(first.id == "BT2627SWRLCP01")
        #expect(first.seasonID == SeasonID(rawValue: "2627"))
        #expect(first.nation == "FIN")
    }

    @Test func competitionStates() throws {
        let races: [Competition] = try fixture("competitions")
        #expect(races[0].state == .scheduled)
        #expect(races[0].distanceKm == "20")
        #expect(!races[0].isRelay)
        #expect(races[1].state == .finished)
        #expect(races[1].isRelay)
    }

    @Test func relayResults() throws {
        let results: RaceResults = try fixture("relay-results")
        #expect(results.standings.count == 1)
        let norway = try #require(results.standings.first)
        #expect(results.legs(of: norway).map(\.name) == ["ULDAL Martin"])
        #expect(norway.misses == 11)
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
    }

    @Test func seasonIDs() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let march = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!
        #expect(SeasonID.containing(october, calendar: calendar).rawValue == "2627")
        #expect(SeasonID.containing(march, calendar: calendar).rawValue == "2627")
        #expect(SeasonID(rawValue: "2627").previous.rawValue == "2526")
        #expect(SeasonID(rawValue: "2627").displayName == "2026-27")
        #expect(Cup.worldCupID(SeasonID(rawValue: "2627"), "SMTS") == "BT2627SWRLCP__SMTS")
    }
}
