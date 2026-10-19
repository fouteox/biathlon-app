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
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard settings.reminderEnabled, !settings.categories.isEmpty else { return }
        guard let races = try? await upcomingRaces(client: client, now: now) else { return }

        let offset = TimeInterval(settings.reminderMinutes * 60)
        let categories = Set(settings.categories.map(\.rawValue))
        for race in races where categories.contains(race.categoryID ?? "") {
            let fireDate = race.startTime.addingTimeInterval(-offset)
            guard fireDate > now, race.state == .scheduled || race.state == .delayed else { continue }
            try? await center.add(request(for: race, minutes: settings.reminderMinutes, fireDate: fireDate))
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

    private static func request(for race: Competition, minutes: Int, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = race.shortDescription
        content.body = String(localized: "Starts in \(minutes) minutes", table: "Notifications")
        content.sound = .default
        content.threadIdentifier = race.id
        content.userInfo = ["raceId": race.id]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix + race.id, content: content, trigger: trigger)
    }
}
