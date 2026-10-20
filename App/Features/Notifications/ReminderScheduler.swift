import BiathlonKit
import Foundation
import UserNotifications
import os

/// Schedules the local "N minutes before the start" reminders.
///
/// The schedule is rebuilt from the IBU calendar each time the app becomes
/// active, when settings change, and when a start time change alert arrives.
enum ReminderScheduler {
    private static let identifierPrefix = "reminder."

    static func refresh(_ preferences: NotificationPreferences, client: IBUClient, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        var reminders: [Reminder] = []
        if preferences.reminderEnabled, !preferences.categories.isEmpty {
            let races: [Competition]
            do {
                races = try await client.upcomingRaces(now: now, horizon: ReminderPlan.horizon)
            } catch {
                // Keep the current reminders when the calendar can't be fetched (e.g. offline).
                Logger.notifications.error(
                    "Calendar for reminders failed: \(String(describing: error), privacy: .public)")
                return
            }
            reminders = ReminderPlan.reminders(
                for: races, categories: preferences.categories, minutesBefore: preferences.reminderMinutes, now: now)
        }
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for reminder in reminders {
            // Measured once: the trigger rejects an interval that isn't positive.
            let interval = reminder.fireDate.timeIntervalSinceNow
            guard interval >= 1 else { continue }
            do {
                try await center.add(
                    request(for: reminder.race, minutes: preferences.reminderMinutes, interval: interval))
            } catch {
                Logger.notifications.error(
                    "Scheduling a reminder failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func request(for race: Competition, minutes: Int, interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = race.shortDescription
        content.body = String(localized: "Starts in \(minutes) minutes")
        content.sound = .default
        // Grouped by event, like the server's alerts.
        content.threadIdentifier = race.eventID
        content.userInfo = ["raceId": race.id]

        // A time interval is absolute, unlike calendar components, which follow the device's time zone.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix + race.id, content: content, trigger: trigger)
    }
}
