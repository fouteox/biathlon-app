import BiathlonKit
import UIKit
import UserNotifications
import os

/// Receives the APNs device token and notifications delivered while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let settings = NotificationSettings()
    let push = PushRegistration()
    let client = IBUClient()

    private var preferenceChanges: Task<Void, Never>?
    private var pendingChange: Task<Void, Never>?
    private var reminderRefresh: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        push.register()
        observePreferences()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await push.didReceive(token: deviceToken, preferences: settings.preferences) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Registration is retried at the next launch.
        Logger.notifications.error("APNs registration failed: \(String(describing: error), privacy: .public)")
    }

    /// UIKit expects the completion handler on the main thread. The async variants of the
    /// delegate methods complete on a background executor, which crashed the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        // Only the server's alerts carry `startTime` (server/src/payload.ts), not the local reminders.
        let isAlert = notification.request.content.userInfo["startTime"] != nil
        Task { @MainActor in
            completionHandler([.banner, .sound, .list])
            if isAlert { self.refreshReminders() }
        }
    }

    // Tapping an alert needs no handling: the app becomes active, which refreshes the reminders.

    /// Applies every change of the preferences, wherever it is made, after a short pause
    /// that coalesces quick successive changes. Syncs run one after another with the
    /// latest preferences, so an older one can't overwrite a newer one.
    private func observePreferences() {
        preferenceChanges = Task {
            for await _ in settings.changes {
                let previous = pendingChange
                previous?.cancel()
                pendingChange = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    await previous?.value
                    await push.update(settings.preferences)
                    refreshReminders()
                }
            }
        }
    }

    /// Rebuilds the local reminders. Refreshes run one after another, each with the
    /// preferences current when it starts, so an older one can't overwrite a newer one.
    func refreshReminders() {
        let previous = reminderRefresh
        reminderRefresh = Task {
            await previous?.value
            await ReminderScheduler.refresh(settings.preferences, client: client)
        }
    }
}
