import BiathlonKit
import Foundation
import UserNotifications

/// Schedules the local "N minutes before the start" reminders.
///
/// The schedule is rebuilt from the IBU calendar each time the app becomes
/// active, when settings change, and when a start time change alert arrives.
enum ReminderScheduler {
    private static let identifierPrefix = "reminder."

    static func refresh(settings: NotificationSettings, client: IBUClient, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        var reminders: [Reminder] = []
        if settings.reminderEnabled, !settings.categories.isEmpty {
            // Keep the current reminders when the calendar can't be fetched (e.g. offline).
            guard let races = try? await client.upcomingRaces(now: now, horizon: ReminderPlan.horizon) else { return }
            reminders = ReminderPlan.reminders(
                for: races, categories: settings.categories, minutesBefore: settings.reminderMinutes, now: now)
        }
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for reminder in reminders {
            // Measured once: the trigger rejects an interval that isn't positive.
            let interval = reminder.fireDate.timeIntervalSinceNow
            guard interval >= 1 else { continue }
            try? await center.add(request(for: reminder.race, minutes: settings.reminderMinutes, interval: interval))
        }
    }

    private static func request(for race: Competition, minutes: Int, interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = race.shortDescription
        content.body = String(localized: "Starts in \(minutes) minutes")
        content.sound = .default
        content.threadIdentifier = race.id
        content.userInfo = ["raceId": race.id]

        // A time interval is absolute, unlike calendar components, which follow the device's time zone.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix + race.id, content: content, trigger: trigger)
    }
}
