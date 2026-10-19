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

    private let serverURL = Bundle.main.serverURL
    private let appAttest = Bundle.main.serverURL.map { AppAttest(serverURL: $0) }

    /// APNs environment matching the `aps-environment` entitlement Xcode signs the build with.
    private var environment: String {
        #if DEBUG
            "sandbox"
        #else
            "production"
        #endif
    }

    /// Registering doesn't prompt the user. It runs at every launch so the
    /// server also learns when alerts were turned off.
    func register() {
        guard serverURL != nil else { return }
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
        guard let serverURL, let appAttest, let deviceToken else { return }
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
            let response = try await appAttest.send(request)
            if !(200..<300).contains(response.statusCode) {
                Logger.notifications.error("Server answered \(response.statusCode) to \(method, privacy: .public)")
            }
        } catch AppAttest.Failure.unsupported {
            // The server only accepts attested devices; the Simulator, for one, can't attest.
            Logger.notifications.notice("App Attest is unavailable, push alerts stay off")
        } catch {
            // Private: the request URL in the error carries the device token.
            Logger.notifications.error("Server sync failed: \(String(describing: error), privacy: .private)")
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
