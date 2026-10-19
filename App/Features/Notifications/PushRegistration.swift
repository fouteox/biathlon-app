import BiathlonKit
import Foundation
import Observation
import UIKit
import os

/// Keeps the notification server and the local reminders in sync with this
/// device's APNs token and the user's preferences.
///
/// Apple advises against caching device tokens, so the token only lives in
/// memory and is requested again at every launch.
final class PushRegistration {
    private var deviceToken: String?

    /// Base URL of the Cloudflare Worker, from the `BiathlonServerURL` Info.plist key.
    private let serverURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BiathlonServerURL") as? String, !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }()

    /// APNs environment matching the `aps-environment` entitlement Xcode signs the build with.
    private var environment: String {
        #if DEBUG
            "sandbox"
        #else
            "production"
        #endif
    }

    private var observation: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?

    /// Registering doesn't prompt the user. It runs at every launch so the
    /// server also learns when alerts were turned off.
    func register() {
        guard serverURL != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Applies every later change of the preferences, wherever it is made.
    func observe(_ settings: NotificationSettings, client: IBUClient) {
        observation = Task {
            for await preferences in Observations { @MainActor in settings.preferences }.dropFirst() {
                scheduleSync(preferences, client: client)
            }
        }
    }

    /// Applies changed preferences after a short pause, coalescing quick successive changes.
    private func scheduleSync(_ preferences: NotificationPreferences, client: IBUClient) {
        pendingSync?.cancel()
        pendingSync = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            if deviceToken == nil { register() }
            await sync(preferences)
            await ReminderScheduler.refresh(preferences, client: client)
        }
    }

    func didReceive(token: Data, preferences: NotificationPreferences) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        await sync(preferences)
    }

    /// Sends the current preferences, or unregisters when no push alert is wanted.
    private func sync(_ preferences: NotificationPreferences) async {
        guard let serverURL, let deviceToken else { return }
        let method = preferences.wantsPush ? "PUT" : "DELETE"
        var request = URLRequest(url: serverURL.appending(path: "v1/devices/\(deviceToken)"))
        request.httpMethod = method
        if preferences.wantsPush {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(
                    Body(
                        environment: environment,
                        categories: preferences.categories.map(\.rawValue).sorted(),
                        cancellation: preferences.cancellationAlerts,
                        rescheduling: preferences.reschedulingAlerts,
                        locale: Locale.current.identifier(.bcp47),
                        timeZone: TimeZone.current.identifier
                    ))
            } catch {
                Logger.notifications.fault(
                    "Encoding the registration failed: \(String(describing: error), privacy: .public)")
                return
            }
        }
        // A failed sync is retried at the next launch or preference change.
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Logger.notifications.error("Server answered \(http.statusCode) to \(method, privacy: .public)")
            }
        } catch {
            Logger.notifications.error("Server sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    private struct Body: Encodable {
        let environment: String
        let categories: [String]
        let cancellation: Bool
        let rescheduling: Bool
        let locale: String
        let timeZone: String
    }
}
