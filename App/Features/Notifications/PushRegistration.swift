import BiathlonKit
import Foundation
import UIKit
import os

/// Keeps the notification server in sync with this device's APNs token and
/// the user's preferences.
///
/// Apple advises against caching device tokens, so the token only lives in
/// memory and is requested again at every launch.
final class PushRegistration {
    private var deviceToken: String?

    private let appAttest: AppAttest?

    init(appAttest: AppAttest?) {
        self.appAttest = appAttest
    }

    /// Registering doesn't prompt the user. It runs at every launch so the
    /// server also learns when alerts were turned off.
    func register() {
        guard appAttest != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sends changed preferences, registering first if alerts were just turned on.
    func update(_ preferences: NotificationPreferences) async {
        if deviceToken == nil { register() }
        await sync(preferences)
    }

    func didReceive(token: Data, preferences: NotificationPreferences) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        await sync(preferences)
    }

    /// Sends the current preferences, or unregisters when no push alert is wanted.
    private func sync(_ preferences: NotificationPreferences) async {
        guard let appAttest, let deviceToken else { return }
        let registration =
            preferences.wantsPush
            ? DeviceRegistration(
                environment: .current,
                categories: preferences.categories,
                cancellation: preferences.cancellationAlerts,
                rescheduling: preferences.reschedulingAlerts,
                locale: Locale.current.identifier(.bcp47),
                timeZone: TimeZone.current.identifier
            ) : nil
        // A failed sync is retried at the next launch or preference change.
        do {
            try await appAttest.send(try .device(token: deviceToken, registration))
        } catch AppAttest.Failure.unsupported {
            // The server only accepts attested devices; the Simulator, for one, can't attest.
            Logger.notifications.notice("App Attest is unavailable, push alerts stay off")
        } catch {
            // Private: the error can carry the device token.
            Logger.notifications.error("Server sync failed: \(String(describing: error), privacy: .private)")
        }
    }
}
