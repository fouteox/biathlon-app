import Foundation
import Testing

@testable import BiathlonKit

struct ReminderPlanTests {
    let now = date("2026-11-26T12:00:00Z")

    @Test func remindsBeforeEachMatchingRace() throws {
        let races: [Competition] = [
            try decode(race("men", start: "2026-11-26T15:15:00Z", category: "SM")),
            try decode(race("women", start: "2026-11-27T12:00:00Z", category: "SW")),
            try decode(race("mixed", start: "2026-11-27T15:00:00Z", category: "MX")),
        ]
        let reminders = ReminderPlan.reminders(for: races, categories: [.men, .women], minutesBefore: 15, now: now)
        #expect(reminders.map(\.race.id) == ["men", "women"])
        #expect(reminders.first?.fireDate == date("2026-11-26T15:00:00Z"))
    }

    @Test func skipsRacesThatAreNotUpcomingOrTooClose() throws {
        let races: [Competition] = [
            try decode(race("cancelled", start: "2026-11-26T18:00:00Z", status: 6, scheduleStatus: "CANCELLED")),
            try decode(race("live", start: "2026-11-26T11:00:00Z", isLive: true)),
            try decode(race("tooClose", start: "2026-11-26T12:10:00Z")),
        ]
        #expect(ReminderPlan.reminders(for: races, categories: [.men], minutesBefore: 15, now: now).isEmpty)
    }

    @Test func upcomingRacesStayWithinTheHorizon() async throws {
        let client = stubClient([
            "Events?Level=1&SeasonId=2627": "["
                + event("past", start: "2026-11-16T12:00:00Z", end: "2026-11-22T12:00:00Z") + ","
                + event("now", start: "2026-11-23T12:00:00Z", end: "2026-11-29T12:00:00Z") + ","
                + event("later", start: "2026-12-10T12:00:00Z", end: "2026-12-14T12:00:00Z") + "]",
            "Competitions?EventId=now": "["
                + race("started", start: "2026-11-26T11:00:00Z") + ","
                + race("soon", start: "2026-11-27T11:00:00Z") + "]",
        ])
        let races = try await client.upcomingRaces(now: now, horizon: ReminderPlan.horizon)
        #expect(races.map(\.id) == ["soon"])
    }

    @Test(.timeLimit(.minutes(1)))
    func loadsTheRacesOfEveryEventTogetherInCalendarOrder() async throws {
        let client = rendezvousClient(
            [
                "Events?Level=1&SeasonId=2627": "["
                    + event("first", start: "2026-11-23T12:00:00Z", end: "2026-11-29T12:00:00Z") + ","
                    + event("second", start: "2026-11-30T12:00:00Z", end: "2026-12-06T12:00:00Z") + "]",
                "Competitions?EventId=first": "[" + race("A", start: "2026-11-27T11:00:00Z") + "]",
                "Competitions?EventId=second": "[" + race("B", start: "2026-12-02T11:00:00Z") + "]",
            ], together: [["Competitions?EventId=first", "Competitions?EventId=second"]])
        let races = try await client.upcomingRaces(now: now, horizon: ReminderPlan.horizon)
        #expect(races.map(\.id) == ["A", "B"])
    }
}
