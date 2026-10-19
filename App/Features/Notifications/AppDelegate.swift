import BiathlonKit
import UIKit
import UserNotifications
import os

/// Receives the APNs device token and notifications delivered while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let settings = NotificationSettings()
    let push = PushRegistration()
    let client = IBUClient()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        push.register()
        push.observe(settings, client: client)
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
            if isAlert { await self.refreshReminders() }
        }
    }

    // Tapping an alert needs no handling: the app becomes active, which refreshes the reminders.

    /// A start time change alert means the local reminder may now be wrong.
    func refreshReminders() async {
        await ReminderScheduler.refresh(settings.preferences, client: client)
    }
}
