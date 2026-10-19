import BiathlonKit
import UIKit
import UserNotifications

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
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await push.didReceive(token: deviceToken, settings: settings) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Registration is retried at the next launch.
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isAlert = notification.request.content.userInfo["startTime"] != nil
        if isAlert { await refreshReminders() }
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let isAlert = response.notification.request.content.userInfo["startTime"] != nil
        if isAlert { await refreshReminders() }
    }

    /// A start time change alert means the local reminder may now be wrong.
    func refreshReminders() async {
        await ReminderScheduler.refresh(settings: settings, client: client)
    }
}
