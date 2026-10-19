import BiathlonKit
import SwiftUI
import UserNotifications

/// Notification preferences, built only from system form controls.
struct NotificationSettingsView: View {
    @Environment(NotificationSettings.self) private var settings
    @Environment(PushRegistration.self) private var push
    @Environment(\.ibu) private var ibu
    @Environment(\.dismiss) private var dismiss
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
                    Text("Notifications are turned off for Biathlon in Settings.")
                }
            }

            Section {
                Toggle("Reminder before the start", isOn: $settings.reminderEnabled)
                if settings.reminderEnabled {
                    Picker("Notify me", selection: $settings.reminderMinutes) {
                        ForEach(NotificationSettings.reminderChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            } footer: {
                Text("Scheduled on this iPhone for races in the coming week.")
            }

            Section {
                Toggle("Race cancelled", isOn: $settings.cancellationAlerts)
                Toggle("Start time changed", isOn: $settings.reschedulingAlerts)
            } header: {
                Text("Alerts")
            }

            Section {
                ForEach(RaceCategory.allCases) { category in
                    Toggle(
                        category.title,
                        isOn: Binding(
                            get: { settings.categories.contains(category) },
                            set: { isOn in
                                if isOn {
                                    settings.categories.insert(category)
                                } else {
                                    settings.categories.remove(category)
                                }
                            }
                        ))
                }
            } header: {
                Text("Races")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { dismiss() }
            }
        }
        .task { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: settings.anyEnabled) { _, enabled in
            if enabled { Task { await requestAuthorization() } }
        }
        .onChange(of: Preferences(settings)) {
            // Owned by PushRegistration, so dismissing the sheet doesn't cancel it.
            push.scheduleSync(settings, client: ibu)
        }
    }

    /// Apple recommends asking for permission in context, when the user turns a notification on.
    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        authorization = await center.notificationSettings().authorizationStatus
    }

    private struct Preferences: Equatable {
        let reminder: Bool, minutes: Int, cancellation: Bool, rescheduling: Bool, categories: Set<RaceCategory>

        init(_ settings: NotificationSettings) {
            reminder = settings.reminderEnabled
            minutes = settings.reminderMinutes
            cancellation = settings.cancellationAlerts
            rescheduling = settings.reschedulingAlerts
            categories = settings.categories
        }
    }
}
