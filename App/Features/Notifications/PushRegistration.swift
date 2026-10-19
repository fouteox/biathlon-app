import BiathlonKit
import Foundation
import UIKit

/// Keeps the notification server in sync with this device's APNs token and preferences.
///
/// Apple advises against caching device tokens, so the token only lives in
/// memory and is requested again at every launch.
@Observable
final class PushRegistration {
    private(set) var deviceToken: String?

    /// Base URL of the Cloudflare Worker, from the `BiathlonServerURL` Info.plist key.
    @ObservationIgnored private let serverURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BiathlonServerURL") as? String, !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }()

    @ObservationIgnored private let session = URLSession.shared

    /// APNs environment matching the `aps-environment` entitlement Xcode signs the build with.
    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    @ObservationIgnored private var pendingSync: Task<Void, Never>?

    /// Registering doesn't prompt the user. It runs at every launch so the
    /// server also learns when alerts were turned off.
    func register() {
        guard serverURL != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Applies changed preferences after a short pause, coalescing quick successive changes.
    func scheduleSync(_ settings: NotificationSettings, client: IBUClient) {
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if deviceToken == nil { register() }
            await sync(settings)
            await ReminderScheduler.refresh(settings: settings, client: client)
        }
    }

    func didReceive(token: Data, settings: NotificationSettings) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        await sync(settings)
    }

    /// Sends the current preferences, or unregisters when no push alert is wanted.
    func sync(_ settings: NotificationSettings) async {
        guard let serverURL, let deviceToken else { return }
        var request = URLRequest(url: serverURL.appending(path: "v1/devices/\(deviceToken)"))
        if settings.wantsPush {
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(Body(
                environment: environment,
                categories: settings.categories.map(\.rawValue).sorted(),
                cancellation: settings.cancellationAlerts,
                rescheduling: settings.reschedulingAlerts,
                locale: Locale.current.identifier(.bcp47),
                timeZone: TimeZone.current.identifier
            ))
        } else {
            request.httpMethod = "DELETE"
        }
        _ = try? await session.data(for: request)
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
