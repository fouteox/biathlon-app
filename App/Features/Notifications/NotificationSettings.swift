import BiathlonKit
import Foundation
import Observation

extension RaceCategory {
    var title: String {
        switch self {
        case .men: String(localized: "Men")
        case .women: String(localized: "Women")
        case .mixed: String(localized: "Mixed")
        }
    }
}

/// What the user asked to be notified of.
struct NotificationPreferences: Equatable, Sendable {
    var reminderEnabled = false
    var reminderMinutes = 15
    var cancellationAlerts = false
    var reschedulingAlerts = false
    var categories = Set(RaceCategory.allCases)

    var anyEnabled: Bool { reminderEnabled || wantsPush }

    /// Push alerts are only useful with at least one alert type and one category.
    var wantsPush: Bool { (cancellationAlerts || reschedulingAlerts) && !categories.isEmpty }
}

/// The user's notification preferences, stored in `UserDefaults`.
@Observable
final class NotificationSettings {
    static let reminderChoices = [5, 10, 15, 30, 60]

    var preferences: NotificationPreferences { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var preferences = NotificationPreferences()
        preferences.reminderEnabled = defaults.bool(forKey: Keys.reminderEnabled)
        let minutes = defaults.integer(forKey: Keys.reminderMinutes)
        if Self.reminderChoices.contains(minutes) { preferences.reminderMinutes = minutes }
        preferences.cancellationAlerts = defaults.bool(forKey: Keys.cancellationAlerts)
        preferences.reschedulingAlerts = defaults.bool(forKey: Keys.reschedulingAlerts)
        if let stored = defaults.stringArray(forKey: Keys.categories) {
            preferences.categories = Set(stored.compactMap(RaceCategory.init(rawValue:)))
        }
        self.preferences = preferences
    }

    private func save() {
        defaults.set(preferences.reminderEnabled, forKey: Keys.reminderEnabled)
        defaults.set(preferences.reminderMinutes, forKey: Keys.reminderMinutes)
        defaults.set(preferences.cancellationAlerts, forKey: Keys.cancellationAlerts)
        defaults.set(preferences.reschedulingAlerts, forKey: Keys.reschedulingAlerts)
        defaults.set(preferences.categories.map(\.rawValue).sorted(), forKey: Keys.categories)
    }

    private enum Keys {
        static let reminderEnabled = "notifications.reminderEnabled"
        static let reminderMinutes = "notifications.reminderMinutes"
        static let cancellationAlerts = "notifications.cancellationAlerts"
        static let reschedulingAlerts = "notifications.reschedulingAlerts"
        static let categories = "notifications.categories"
    }
}
