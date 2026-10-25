import BiathlonKit
import Foundation
import Testing

@testable import Biathlon

struct NotificationSettingsTests {
    @Test func keepsThePreferencesAcrossLaunches() throws {
        let defaults = try UserDefaults.empty()
        var preferences = NotificationPreferences()
        preferences.reminderEnabled = true
        preferences.reminderMinutes = 30
        preferences.reschedulingAlerts = true
        preferences.categories = [.women, .mixed]

        let settings = NotificationSettings(defaults: defaults)
        settings.preferences = preferences

        #expect(NotificationSettings(defaults: defaults).preferences == preferences)
    }

    @Test func dropsAReminderDelayNoLongerOffered() throws {
        let defaults = try UserDefaults.empty()
        defaults.set(7, forKey: "notifications.reminderMinutes")
        #expect(NotificationSettings(defaults: defaults).preferences.reminderMinutes == 15)
    }

    /// Quick successive changes reach the code applying them as the latest one.
    @Test func publishesTheLatestChange() async throws {
        let settings = NotificationSettings(defaults: try .empty())
        settings.preferences.reminderEnabled = true
        settings.preferences.reminderMinutes = 30

        for await change in settings.changes {
            #expect(change.reminderEnabled)
            #expect(change.reminderMinutes == 30)
            break
        }
    }
}
