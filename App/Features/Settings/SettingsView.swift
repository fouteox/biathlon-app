import BiathlonKit
import SwiftUI
import UserNotifications
import os

/// App settings: notification preferences and where the data comes from, built only from
/// system form controls.
struct SettingsView: View {
    @Environment(NotificationSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
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

            Section("Notifications") {
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
                Toggle("Race cancelled", isOn: $settings.preferences.cancellationAlerts)
                Toggle("Start time changed", isOn: $settings.preferences.reschedulingAlerts)
            }

            Section("Notify for") {
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
            }

            #if DEBUG
                Section {
                    NavigationLink {
                        LiveActivityDemoView()
                    } label: {
                        Label {
                            Text(verbatim: "Live Activity demo")
                        } icon: {
                            Image(systemName: "hammer")
                        }
                    }
                } header: {
                    Text(verbatim: "Developer")
                }
            #endif

            Section("About") {
                Link(destination: URL(string: "https://www.biathlonresults.com")!) {
                    LabeledContent("Data", value: "IBU Datacenter")
                }
                if let privacyPolicy = Bundle.main.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyPolicy)
                }
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    LabeledContent("Version", value: version)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
            }
        }
        .task { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: settings.preferences.anyEnabled) { _, enabled in
            if enabled { Task { await requestAuthorization() } }
        }
    }

    /// Apple recommends asking for permission in context, when the user turns a notification on.
    /// `providesAppNotificationSettings` adds a button to this screen in Settings > Notifications.
    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .providesAppNotificationSettings])
        } catch {
            Logger.notifications.error("Authorization request failed: \(String(describing: error), privacy: .public)")
        }
        authorization = await center.notificationSettings().authorizationStatus
    }
}
