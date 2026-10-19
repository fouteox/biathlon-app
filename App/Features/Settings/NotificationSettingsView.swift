import BiathlonKit
import SwiftUI
import UserNotifications
import os

/// Notification preferences, built only from system form controls.
struct NotificationSettingsView: View {
    @Environment(NotificationSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var settings = settings
        Form {
            if authorization == .denied {
                Section {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Notifications are turned off in Settings.")
                }
            }

            Section {
                Toggle("Reminder before the start", isOn: $settings.preferences.reminderEnabled)
                if settings.preferences.reminderEnabled {
                    Picker("Notify me", selection: $settings.preferences.reminderMinutes) {
                        ForEach(NotificationSettings.reminderChoices, id: \.self) { minutes in
                            Text(
                                Duration.seconds(minutes * 60), format: .units(allowed: [.minutes], width: .abbreviated)
                            )
                            .tag(minutes)
                        }
                    }
                }
            } footer: {
                Text("Scheduled on this iPhone for races in the coming week.")
            }

            Section {
                Toggle("Race cancelled", isOn: $settings.preferences.cancellationAlerts)
                Toggle("Start time changed", isOn: $settings.preferences.reschedulingAlerts)
            } header: {
                Text("Alerts")
            }

            Section {
                ForEach(RaceCategory.allCases) { category in
                    Toggle(
                        category.title,
                        isOn: Binding(
                            get: { settings.preferences.categories.contains(category) },
                            set: { isOn in
                                if isOn {
                                    settings.preferences.categories.insert(category)
                                } else {
                                    settings.preferences.categories.remove(category)
                                }
                            }
                        ))
                }
            } header: {
                Text("Races")
            }
        }
        .navigationTitle("Notifications")
        .task { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: settings.preferences.anyEnabled) { _, enabled in
            if enabled { Task { await requestAuthorization() } }
        }
    }

    /// Apple recommends asking for permission in context, when the user turns a notification on.
    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Logger.notifications.error("Authorization request failed: \(String(describing: error), privacy: .public)")
        }
        authorization = await center.notificationSettings().authorizationStatus
    }
}
