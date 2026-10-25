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

    /// The push-to-start token, in hex like a device token. Kept in memory, like the device
    /// token (PushRegistration): ActivityKit gives it at every launch. Only the one last sent
    /// is stored, for the deletion.
    private(set) var token: String? = Activity<RaceActivityAttributes>.pushToStartToken.map(LiveActivityStarts.hex)

    @ObservationIgnored private let appAttest: AppAttest?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tokenUpdates: Task<Void, Never>?
    /// The last sync, which the next one waits for: the server and the stored token see them in order.
    @ObservationIgnored private var lastSync: Task<Void, Never>?

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
    /// wanted, after the previous sync. A failed sync is retried at the next launch or change.
    func sync(_ registration: Registration) async {
        let previous = lastSync
        let current = Task {
            await previous?.value
            await send(registration)
        }
        lastSync = current
        await current.value
    }

    private func send(_ registration: Registration) async {
        guard let appAttest else { return }
        let favorites = registration.favorites
        let wanted = registration.isEnabled && !favorites.isEmpty
        // A deletion names the token the favorites were sent with: ActivityKit gives none
        // while Live Activities are turned off in Settings.
        let token = wanted ? registration.token : defaults.string(forKey: Keys.registeredToken)
        guard let token else { return }
        do {
            let request = try SignedRequest.liveActivityStarts(
                token: token,
                wanted ? LiveActivityStartsRegistration(environment: .current, favorites: favorites) : nil)
            // Set before the PUT: the server may store it even if its answer is lost.
            if wanted { defaults.set(token, forKey: Keys.registeredToken) }
            try await appAttest.send(request)
            if !wanted { defaults.removeObject(forKey: Keys.registeredToken) }
        } catch AppAttest.Failure.unsupported {
            Logger.notifications.notice("App Attest is unavailable, Live Activities for favorites stay off")
        } catch {
            // Private: the error can carry the token.
            Logger.notifications.error(
                "Sending the Live Activity favorites failed: \(String(describing: error), privacy: .private)")
        }
    }

    private nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private enum Keys {
        static let isEnabled = "liveActivities.favoriteStarts"
        /// The last token sent with favorites the server may hold, until they are deleted.
        static let registeredToken = "liveActivities.favoriteStartsToken"
    }
}
