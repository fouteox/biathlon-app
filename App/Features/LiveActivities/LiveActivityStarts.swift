import ActivityKit
import BiathlonKit
import Foundation
import Observation
import os

/// Lets the server start a race's Live Activity when one of the user's favorites is on the
/// start list (server/src/liveStarts.ts), with ActivityKit's push-to-start token.
///
/// Off by default: Apple's guidelines ask to start Live Activities at times people expect,
/// and to let them turn them off easily in the app. The favorites only reach
/// the server while it is on, and are deleted from it when it is turned off or none is left.
@Observable
final class LiveActivityStarts {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// The push-to-start token, in hex like a device token. Kept in memory only, like the
    /// device token (PushRegistration): ActivityKit gives it at every launch.
    private(set) var token: String? = Activity<RaceActivityAttributes>.pushToStartToken.map(LiveActivityStarts.hex)

    @ObservationIgnored private let serverURL = Bundle.main.serverURL
    @ObservationIgnored private let appAttest: AppAttest?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tokenUpdates: Task<Void, Never>?

    init(appAttest: AppAttest?, defaults: UserDefaults = .standard) {
        self.appAttest = appAttest
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        tokenUpdates = Task { [weak self] in
            for await token in Activity<RaceActivityAttributes>.pushToStartTokenUpdates {
                self?.token = Self.hex(token)
            }
        }
    }

    isolated deinit {
        tokenUpdates?.cancel()
    }

    /// What the server should know: sent again whenever it changes.
    nonisolated struct Registration: Equatable, Sendable {
        let token: String?
        let isEnabled: Bool
        let favorites: FavoriteSet
    }

    func registration(favorites: FavoriteSet) -> Registration {
        Registration(token: token, isEnabled: isEnabled, favorites: favorites)
    }

    /// Sends the favorites to the server, or deletes them from it once they are no longer
    /// wanted. A failed sync is retried at the next launch or change.
    func sync(_ registration: Registration) async {
        guard let serverURL, let appAttest, let token = registration.token else { return }
        let favorites = registration.favorites
        let wanted = registration.isEnabled && !favorites.isEmpty
        // Nothing to delete unless favorites may have reached the server.
        guard wanted || defaults.bool(forKey: Keys.mayBeRegistered) else { return }
        var request = URLRequest(url: serverURL.appending(path: "v1/live-activity-starts/\(token)"))
        request.httpMethod = wanted ? "PUT" : "DELETE"
        if wanted {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(
                    Body(
                        environment: APNsEnvironment.current.rawValue,
                        athletes: favorites.athleteIDs.sorted(),
                        nations: favorites.nations.sorted()))
            } catch {
                Logger.notifications.fault(
                    "Encoding the favorites failed: \(String(describing: error), privacy: .public)")
                return
            }
        }
        // Set before the PUT: the server may store it even if its answer is lost.
        if wanted { defaults.set(true, forKey: Keys.mayBeRegistered) }
        do {
            let response = try await appAttest.send(request)
            guard (200..<300).contains(response.statusCode) else {
                Logger.notifications.error(
                    "Server answered \(response.statusCode) to the Live Activity favorites")
                return
            }
            if !wanted { defaults.set(false, forKey: Keys.mayBeRegistered) }
        } catch AppAttest.Failure.unsupported {
            Logger.notifications.notice("App Attest is unavailable, Live Activities for favorites stay off")
        } catch {
            // Private: the request URL in the error carries the token.
            Logger.notifications.error(
                "Sending the Live Activity favorites failed: \(String(describing: error), privacy: .private)")
        }
    }

    private nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private struct Body: Encodable {
        let environment: String
        let athletes: [String]
        let nations: [String]
    }

    private enum Keys {
        static let isEnabled = "liveActivities.favoriteStarts"
        /// Whether the server may hold this install's favorites.
        static let mayBeRegistered = "liveActivities.favoriteStartsMayBeRegistered"
    }
}
