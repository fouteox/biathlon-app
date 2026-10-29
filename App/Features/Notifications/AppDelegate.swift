import BiathlonKit
import UIKit
import UserNotifications
import os

/// Receives the APNs device token, notifications delivered while the app is open, and the
/// system's requests to show the notification settings.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let settings = NotificationSettings()
    let settingsPresentation = SettingsPresentation()
    /// The notification server, `nil` for a build without one.
    let server: ServerClient?
    let push: PushRegistration
    let liveActivities: LiveActivities
    let liveActivityStarts: LiveActivityStarts
    private let notificationCenter = UNUserNotificationCenter.current()
    let client: IBUClient
    let wikidata: WikidataClient
    let news: NewsClient
    /// A Debug build launched with `--sample-data`, as the UI tests launch it, runs on the fictional data of
    /// `IBUClient.sample`, without a server, and keeps its favorites in memory: nothing it shows depends
    /// on the network or on an earlier launch.
    let runsOnSampleData: Bool

    private var preferenceChanges: Task<Void, Never>?
    private var pendingChange: Task<Void, Never>?
    private var reminderRefresh: Task<Void, Never>?

    override init() {
        let runsOnSampleData = Self.asksForSampleData(arguments: ProcessInfo.processInfo.arguments)
        self.runsOnSampleData = runsOnSampleData
        let (client, server) = Self.clients(sampleData: runsOnSampleData)
        self.client = client
        self.server = server
        wikidata = Self.wikidata(sampleData: runsOnSampleData)
        news = Self.news(sampleData: runsOnSampleData)
        // One for every request to the server: it attests a single key for the install.
        let appAttest = server.map { AppAttest(server: $0) }
        push = PushRegistration(appAttest: appAttest)
        liveActivityStarts = LiveActivityStarts(appAttest: appAttest)
        liveActivities = LiveActivities(server: server, starts: liveActivityStarts)
        super.init()
    }

    static func asksForSampleData(arguments: [String]) -> Bool {
        #if DEBUG
            arguments.contains("--sample-data")
        #else
            false
        #endif
    }

    /// IBU data goes through the server's cache when there is a server, to spare the IBU API.
    static func clients(sampleData: Bool) -> (ibu: IBUClient, server: ServerClient?) {
        #if DEBUG
            if sampleData { return (.sample(now: .now), nil) }
        #endif
        let server = Bundle.main.serverURL.map { ServerClient(baseURL: $0) }
        return (IBUClient(baseURL: server?.baseURL.appending(path: "ibu/") ?? IBUClient.ibuBaseURL), server)
    }

    static func wikidata(sampleData: Bool) -> WikidataClient {
        #if DEBUG
            if sampleData { return .sample }
        #endif
        return WikidataClient(userAgent: Bundle.main.wikimediaUserAgent)
    }

    static func news(sampleData: Bool) -> NewsClient {
        #if DEBUG
            if sampleData { return .sample(now: .now) }
        #endif
        return NewsClient()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        notificationCenter.delegate = self
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
    /// delegate methods complete on a background executor, which crashed the app: Apple
    /// forums thread 796407 (https://developer.apple.com/forums/thread/796407, FB19519575),
    /// with no confirmed fix. Re-test the async variants on a device under Xcode 27 before
    /// removing this workaround.
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

    /// Called from the button iOS shows in Settings > Notifications, which the app asks for with
    /// `providesAppNotificationSettings`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in self.settingsPresentation.isPresented = true }
    }

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
            await ReminderScheduler.refresh(settings.preferences, client: client, center: notificationCenter)
        }
    }
}
