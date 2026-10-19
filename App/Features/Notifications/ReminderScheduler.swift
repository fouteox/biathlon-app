import BiathlonKit
import Foundation
import UserNotifications

/// Schedules the local "N minutes before the start" reminders.
///
/// The schedule is rebuilt from the IBU calendar each time the app becomes
/// active, when settings change, and when a start time change alert arrives.
enum ReminderScheduler {
    private static let identifierPrefix = "reminder."
    /// Only races in the coming week are scheduled; later ones are added on a later refresh.
    private static let horizon: TimeInterval = 7 * 24 * 60 * 60

    static func refresh(settings: NotificationSettings, client: IBUClient, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        var races: [Competition] = []
        if settings.reminderEnabled, !settings.categories.isEmpty {
            // Keep the current reminders when the calendar can't be fetched (e.g. offline).
            guard let fetched = try? await upcomingRaces(client: client, now: now) else { return }
            races = fetched
        }
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let offset = TimeInterval(settings.reminderMinutes * 60)
        let categories = Set(settings.categories.map(\.rawValue))
        for race in races where categories.contains(race.categoryID ?? "") {
            // Measured once: the trigger rejects an interval that isn't positive.
            let interval = race.startTime.addingTimeInterval(-offset).timeIntervalSinceNow
            guard interval >= 1, race.state == .scheduled || race.state == .delayed else { continue }
            try? await center.add(request(for: race, minutes: settings.reminderMinutes, interval: interval))
        }
    }

    private static func upcomingRaces(client: IBUClient, now: Date) async throws -> [Competition] {
        let end = now.addingTimeInterval(horizon)
        let events = try await client.events(season: SeasonID.containing(now))
            .filter { $0.endDate >= now && $0.startDate <= end }
        var races: [Competition] = []
        for event in events {
            races += try await client.competitions(eventID: event.id)
        }
        return races.filter { $0.startTime > now && $0.startTime <= end }
    }

    private static func request(for race: Competition, minutes: Int, interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = race.shortDescription
        content.body = String(localized: "Starts in \(minutes) minutes", table: "Notifications")
        content.sound = .default
        content.threadIdentifier = race.id
        content.userInfo = ["raceId": race.id]

        // A time interval is absolute, unlike calendar components, which follow the device's time zone.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix + race.id, content: content, trigger: trigger)
    }
}
