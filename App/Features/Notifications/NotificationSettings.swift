import Foundation
import Observation

/// IBU race categories (`catId`) the user can subscribe to.
enum RaceCategory: String, CaseIterable, Codable, Identifiable {
    case men = "SM"
    case women = "SW"
    case mixed = "MX"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .men: String(localized: "Men")
        case .women: String(localized: "Women")
        case .mixed: String(localized: "Mixed")
        }
    }
}

/// The user's notification preferences, stored in `UserDefaults`.
@Observable
final class NotificationSettings {
    static let reminderChoices = [5, 10, 15, 30, 60]

    var reminderEnabled: Bool { didSet { save() } }
    var reminderMinutes: Int { didSet { save() } }
    var cancellationAlerts: Bool { didSet { save() } }
    var reschedulingAlerts: Bool { didSet { save() } }
    var categories: Set<RaceCategory> { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reminderEnabled = defaults.bool(forKey: Keys.reminderEnabled)
        let minutes = defaults.integer(forKey: Keys.reminderMinutes)
        reminderMinutes = Self.reminderChoices.contains(minutes) ? minutes : 15
        cancellationAlerts = defaults.bool(forKey: Keys.cancellationAlerts)
        reschedulingAlerts = defaults.bool(forKey: Keys.reschedulingAlerts)
        let stored = defaults.stringArray(forKey: Keys.categories)?.compactMap(RaceCategory.init(rawValue:))
        categories = Set(stored ?? RaceCategory.allCases)
    }

    var anyEnabled: Bool { reminderEnabled || wantsPush }

    /// Push alerts are only useful with at least one alert type and one category.
    var wantsPush: Bool { (cancellationAlerts || reschedulingAlerts) && !categories.isEmpty }

    private func save() {
        defaults.set(reminderEnabled, forKey: Keys.reminderEnabled)
        defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
        defaults.set(cancellationAlerts, forKey: Keys.cancellationAlerts)
        defaults.set(reschedulingAlerts, forKey: Keys.reschedulingAlerts)
        defaults.set(categories.map(\.rawValue).sorted(), forKey: Keys.categories)
    }

    private enum Keys {
        static let reminderEnabled = "notifications.reminderEnabled"
        static let reminderMinutes = "notifications.reminderMinutes"
        static let cancellationAlerts = "notifications.cancellationAlerts"
        static let reschedulingAlerts = "notifications.reschedulingAlerts"
        static let categories = "notifications.categories"
    }
}
