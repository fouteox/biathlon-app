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
        #expect(SeasonID.containing(date("2026-10-19T12:00:00Z")).rawValue == "2627")
        #expect(SeasonID.containing(date("2027-03-01T12:00:00Z")).rawValue == "2627")
        #expect(SeasonID.containing(date("2026-06-30T23:59:00Z")).rawValue == "2526")
        #expect(SeasonID.recent(3, now: date("2026-10-19T12:00:00Z")).map(\.rawValue) == ["2627", "2526", "2425"])
        #expect(SeasonID(rawValue: "2627").previous.rawValue == "2526")
        #expect(SeasonID(rawValue: "2627").displayName == "2026-27")
    }

    /// Real IDs: `BT2425SWRLCP01` (Kontiolahti), `BT2425SWRLCH__` (Lenzerheide).
    @Test func worldChampionships() throws {
        let championships: BiathlonEvent = try decode(
            event("BT2425SWRLCH__", start: "2025-02-11T12:00:00Z", end: "2025-02-23T12:00:00Z"))
        #expect(championships.isWorldChampionships)
    }
}
