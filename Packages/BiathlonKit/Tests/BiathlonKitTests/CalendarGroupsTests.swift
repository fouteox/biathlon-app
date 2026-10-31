import Foundation
import Testing

@testable import BiathlonKit

struct CalendarGroupsTests {
    /// Paris: the IBU's noon UTC dates fall on the same day, its 23:30 UTC starts on the next.
    static let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    static let events: [BiathlonEvent] = try! [
        decode(event("E3", start: "2027-01-07T12:00:00Z", end: "2027-01-10T12:00:00Z")),
        decode(event("E1", start: "2026-11-28T12:00:00Z", end: "2026-12-06T12:00:00Z")),
        decode(event("E2", start: "2026-12-11T12:00:00Z", end: "2026-12-14T12:00:00Z")),
    ]

    @Test func groupsEventsByMonthInDateOrder() throws {
        let groups = Self.events.groupedByMonth(calendar: Self.paris)

        #expect(
            groups.map { Self.paris.dateComponents([.year, .month], from: $0.start) }.map { "\($0.year!)-\($0.month!)" }
                == ["2026-11", "2026-12", "2027-1"])
        #expect(groups.map { $0.items.map(\.id) } == [["E1"], ["E2"], ["E3"]])
    }

    /// An event starting on November 28 at noon UTC belongs to November, whichever month it ends in.
    @Test func anEventBelongsToTheMonthItStartsIn() throws {
        let groups = Self.events.groupedByMonth(calendar: Self.paris)
        #expect(groups.first?.items.map(\.id) == ["E1"])
    }

    @Test func groupsRacesByLocalDay() throws {
        // 23:30 UTC on the 5th is already the 6th in Paris.
        let races: [Competition] = try [
            decode(race("B", start: "2026-12-05T23:30:00Z")),
            decode(race("A", start: "2026-12-05T13:15:00Z")),
            decode(race("C", start: "2026-12-06T11:00:00Z")),
        ]
        let groups = races.groupedByDay(calendar: Self.paris)

        #expect(groups.map { Self.paris.component(.day, from: $0.start) } == [5, 6])
        #expect(groups.map { $0.items.map(\.id) } == [["A"], ["B", "C"]])
    }

    @Test func anEventIsUnderwayFromItsFirstDayToTheEndOfItsLast() throws {
        let event = Self.events[1]  // E1: November 28 to December 6
        #expect(event.phase(at: date("2026-11-27T23:59:00Z"), calendar: .gmt) == .upcoming)
        #expect(event.phase(at: date("2026-11-28T00:00:00Z"), calendar: .gmt) == .underway)
        #expect(event.phase(at: date("2026-12-06T23:59:00Z"), calendar: .gmt) == .underway)
        #expect(event.phase(at: date("2026-12-07T00:00:00Z"), calendar: .gmt) == .past)
    }

    @Test func theCalendarOpensOnTheEventUnderwayOtherwiseTheNextOne() throws {
        #expect(Self.events.eventToShow(at: date("2026-10-31T12:00:00Z"), calendar: .gmt)?.id == "E1")
        #expect(Self.events.eventToShow(at: date("2026-12-01T12:00:00Z"), calendar: .gmt)?.id == "E1")
        #expect(Self.events.eventToShow(at: date("2026-12-08T12:00:00Z"), calendar: .gmt)?.id == "E2")
        // After the season's last event, the calendar stays on it.
        #expect(Self.events.eventToShow(at: date("2027-06-01T12:00:00Z"), calendar: .gmt)?.id == "E3")
        #expect([BiathlonEvent]().eventToShow(at: .now, calendar: .gmt) == nil)
    }
}

extension Calendar {
    fileprivate static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
