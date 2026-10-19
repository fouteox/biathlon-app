import Foundation

/// A local "N minutes before the start" reminder.
public struct Reminder: Hashable, Sendable {
    public let race: Competition
    public let fireDate: Date
}

public enum ReminderPlan {
    /// Only races in the coming week are scheduled; later ones are added on a later refresh.
    public static let horizon: TimeInterval = 7 * 24 * 60 * 60

    /// Reminders for the upcoming races of the chosen categories, skipping
    /// those that would fire in less than a second.
    public static func reminders(
        for races: [Competition], categories: Set<RaceCategory>, minutesBefore: Int, now: Date
    ) -> [Reminder] {
        races.compactMap { race in
            guard race.state == .scheduled, let category = race.category, categories.contains(category) else {
                return nil
            }
            let fireDate = race.startTime.addingTimeInterval(-TimeInterval(minutesBefore * 60))
            guard fireDate.timeIntervalSince(now) >= 1 else { return nil }
            return Reminder(race: race, fireDate: fireDate)
        }
    }
}

extension IBUClient {
    /// Races starting after `now` and within `horizon`.
    public func upcomingRaces(now: Date, horizon: TimeInterval) async throws -> [Competition] {
        let end = now.addingTimeInterval(horizon)
        let events = try await events(season: SeasonID.containing(now))
            .filter { $0.endDate >= now && $0.startDate <= end }
        var races: [Competition] = []
        for event in events {
            races += try await competitions(eventID: event.id)
        }
        return races.filter { $0.startTime > now && $0.startTime <= end }
    }
}
