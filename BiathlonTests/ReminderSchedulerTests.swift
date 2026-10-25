import BiathlonKit
import Foundation
import Testing
import UserNotifications

@testable import Biathlon

struct ReminderSchedulerTests {
    let now = Date.now
    var preferences = NotificationPreferences()

    init() {
        preferences.reminderEnabled = true
        preferences.reminderMinutes = 15
    }

    @Test func replacesTheRemindersAndKeepsTheOtherNotifications() async throws {
        let start = now.addingTimeInterval(24 * 60 * 60)
        let center = FakeNotificationCenter(pending: ["reminder.OLD", "other"])

        await ReminderScheduler.refresh(preferences, client: calendar(raceStart: start), center: center, now: now)

        #expect(center.requests.map(\.identifier) == ["other", "reminder.BT2627SWRLCP01SMIN"])
        let trigger = try #require(center.requests.last?.trigger as? UNTimeIntervalNotificationTrigger)
        // Measured from the real clock, a moment after `now`.
        #expect(abs(trigger.timeInterval - (start.timeIntervalSince(now) - 15 * 60)) < 60)
    }

    @Test func keepsTheRemindersWhenTheCalendarIsUnavailable() async {
        let center = FakeNotificationCenter(pending: ["reminder.OLD", "other"])

        await ReminderScheduler.refresh(preferences, client: calendar(status: 503), center: center, now: now)

        #expect(center.requests.map(\.identifier) == ["reminder.OLD", "other"])
    }

    @Test func removesTheRemindersOnceTurnedOff() async {
        let center = FakeNotificationCenter(pending: ["reminder.OLD", "other"])
        var preferences = preferences
        preferences.reminderEnabled = false

        await ReminderScheduler.refresh(preferences, client: calendar(status: 503), center: center, now: now)

        #expect(center.requests.map(\.identifier) == ["other"])
    }

    /// The IBU calendar, with an event around `now` and its men's race at `raceStart`.
    private func calendar(raceStart: Date? = nil, status: Int = 200) -> IBUClient {
        let now = now
        let start = (raceStart ?? now).formatted(.iso8601)
        return IBUClient { request in
            let url = try #require(request.url)
            let body =
                switch url.lastPathComponent {
                case "Events":
                    """
                    [{"EventId":"BT2627SWRLCP01","ShortDescription":"Kontiolahti","Nat":"FIN",\
                    "StartDate":"\(now.addingTimeInterval(-86_400).formatted(.iso8601))",\
                    "EndDate":"\(now.addingTimeInterval(3 * 86_400).formatted(.iso8601))"}]
                    """
                case "Competitions":
                    """
                    [{"RaceId":"BT2627SWRLCP01SMIN","catId":"SM","ShortDescription":"Men 20 km Individual",\
                    "StartTime":"\(start)","StatusId":1,"ScheduleStatus":"SCHEDULED","IsLive":false}]
                    """
                default: ""
                }
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return (Data(body.utf8), response)
        }
    }
}
