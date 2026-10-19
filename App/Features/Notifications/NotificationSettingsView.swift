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
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        Text("Open Settings", tableName: "Notifications")
                    }
                } footer: {
                    Text("Notifications are turned off for Biathlon in Settings.", tableName: "Notifications")
                }
            }

            Section {
                Toggle(isOn: $settings.reminderEnabled) {
                    Text("Reminder before the start", tableName: "Notifications")
                }
                if settings.reminderEnabled {
                    Picker(selection: $settings.reminderMinutes) {
                        ForEach(NotificationSettings.reminderChoices, id: \.self) { minutes in
                            Text("\(minutes) min", tableName: "Notifications").tag(minutes)
                        }
                    } label: {
                        Text("Notify me", tableName: "Notifications")
                    }
                }
            } footer: {
                Text("Scheduled on this iPhone for races in the coming week.", tableName: "Notifications")
            }

            Section {
                Toggle(isOn: $settings.cancellationAlerts) {
                    Text("Race cancelled", tableName: "Notifications")
                }
                Toggle(isOn: $settings.reschedulingAlerts) {
                    Text("Start time changed", tableName: "Notifications")
                }
            } header: {
                Text("Alerts", tableName: "Notifications")
            }

            Section {
                ForEach(RaceCategory.allCases) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { settings.categories.contains(category) },
                        set: { isOn in
                            if isOn { settings.categories.insert(category) } else { settings.categories.remove(category) }
                        }
                    ))
                }
            } header: {
                Text("Races", tableName: "Notifications")
            }
        }
        .navigationTitle(Text("Notifications", tableName: "Notifications"))
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
        .task(id: Preferences(settings)) {
            // Coalesces quick successive changes into one refresh.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if settings.wantsPush, push.deviceToken == nil { push.register() }
            await push.sync(settings)
            await ReminderScheduler.refresh(settings: settings, client: ibu)
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
