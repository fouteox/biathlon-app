import BiathlonKit
import EventKit
import Foundation
import Testing

@testable import Biathlon

struct RaceCalendarEntryTests {
    private static let start = Date(timeIntervalSince1970: 1_795_706_100)  // 2026-11-26 15:15 UTC

    private static func race() throws -> Competition {
        try JSONDecoder.ibu.decode(
            Competition.self,
            from: Data(
                """
                {"RaceId": "BT2627SWRLCP01SMSP", "ShortDescription": "Men 10 km Sprint",
                 "StartTime": "2026-11-26T15:15:00Z", "StatusId": 1}
                """.utf8))
    }

    private static func event() throws -> BiathlonEvent {
        try JSONDecoder.ibu.decode(
            BiathlonEvent.self,
            from: Data(
                """
                {"EventId": "BT2627SWRLCP01", "ShortDescription": "Kontiolahti",
                 "StartDate": "2026-11-26T00:00:00Z", "EndDate": "2026-11-30T00:00:00Z", "Nat": "FIN"}
                """.utf8))
    }

    @Test func namesTheRaceInTheAppsLanguageAndPlacesItAtItsEvent() throws {
        let entry = RaceCalendarEntry(race: try Self.race(), event: try Self.event())

        #expect(entry.id == "BT2627SWRLCP01SMSP")
        #expect(entry.title == String(localized: RaceKind.menSprint.title))
        #expect(entry.start == Self.start)
        #expect(entry.location == "Kontiolahti")
    }

    @Test func hasNoPlaceWithoutItsEvent() throws {
        #expect(RaceCalendarEntry(race: try Self.race(), event: nil).location == nil)
    }

    /// The IBU gives no end: the event ends when it starts, which EventKit accepts.
    @Test func makesAnEventThatEndsWhenTheRaceStarts() throws {
        let event = RaceCalendarEntry(race: try Self.race(), event: try Self.event()).event(in: EKEventStore())

        #expect(event.title == String(localized: RaceKind.menSprint.title))
        #expect(event.startDate == Self.start)
        #expect(event.endDate == Self.start)
        #expect(event.location == "Kontiolahti")
    }
}
