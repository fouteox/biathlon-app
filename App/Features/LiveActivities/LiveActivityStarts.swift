import ActivityKit
import BiathlonKit
import Foundation
import Observation
import os

/// Lets the server start a race's Live Activity shortly before the race (server/src/liveStarts.ts),
/// with ActivityKit's push-to-start token: for the later races the user follows, and, when it is
/// on, when one of the user's favorites is on the start list.
///
/// Starting for favorites is off by default: Apple's guidelines ask to start Live Activities at
/// times people expect, and to let them turn them off easily in the app. The favorites only reach
/// the server while it is on; the server's copy is deleted once nothing is left to follow.
@Observable
final class LiveActivityStarts {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// The later races the user follows, until their activity starts.
    private(set) var followedRaces: FollowedRaces {
        didSet { defaults.set(try? JSONEncoder().encode(followedRaces), forKey: Keys.followedRaces) }
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
        followedRaces =
            defaults.data(forKey: Keys.followedRaces)
            .flatMap { try? JSONDecoder().decode(FollowedRaces.self, from: $0) }?
            .pruned(at: .now) ?? FollowedRaces()
        tokenUpdates = Task { [weak self] in
            for await token in Activity<RaceActivityAttributes>.pushToStartTokenUpdates {
                self?.token = Self.hex(token)
            }
        }
    }

    isolated deinit {
        tokenUpdates?.cancel()
    }

    /// Has the server start the race's activity shortly before its start.
    func follow(_ raceID: String, startingAt start: Date) {
        followedRaces.follow(raceID, startingAt: start)
    }

    func unfollow(_ raceID: String) {
        guard followedRaces.contains(raceID) else { return }
        followedRaces.unfollow(raceID)
    }

    /// What the server should know: sent again whenever it changes.
    nonisolated struct Registration: Equatable, Sendable {
        let token: String?
        let isEnabled: Bool
        let favorites: FavoriteSet
        let races: [String]

        /// What the server stores, `nil` when nothing is left to follow: the favorites only
        /// while starting for them is on.
        func body(environment: APNsEnvironment) -> LiveActivityStartsRegistration? {
            let favorites = isEnabled ? favorites : FavoriteSet(athleteIDs: [], nations: [])
            guard !favorites.isEmpty || !races.isEmpty else { return nil }
            return LiveActivityStartsRegistration(environment: environment, favorites: favorites, races: races)
        }
    }

    func registration(favorites: FavoriteSet) -> Registration {
        Registration(
            token: token, isEnabled: isEnabled, favorites: favorites,
            races: followedRaces.pruned(at: .now).raceIDs)
    }

    /// Sends the races and favorites to the server, or deletes them from it once nothing is left
    /// to follow, after the previous sync. A failed sync is retried at the next launch or change.
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
        let body = registration.body(environment: .current)
        let wanted = body != nil
        // A deletion names the token the registration was sent with: ActivityKit gives none
        // while Live Activities are turned off in Settings.
        let token = wanted ? registration.token : defaults.string(forKey: Keys.registeredToken)
        guard let token else { return }
        do {
            let request = try SignedRequest.liveActivityStarts(token: token, body)
            // Set before the PUT: the server may store it even if its answer is lost.
            if wanted { defaults.set(token, forKey: Keys.registeredToken) }
            try await appAttest.send(request)
            if !wanted { defaults.removeObject(forKey: Keys.registeredToken) }
        } catch AppAttest.Failure.unsupported {
            Logger.notifications.notice("App Attest is unavailable, the server starts no Live Activity")
        } catch {
            // Private: the error can carry the token.
            Logger.notifications.error(
                "Sending the Live Activity starts failed: \(String(describing: error), privacy: .private)")
        }
    }

    private nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private enum Keys {
        static let isEnabled = "liveActivities.favoriteStarts"
        static let followedRaces = "liveActivities.followedRaces"
        /// The last token sent with a registration the server may hold, until it is deleted.
        static let registeredToken = "liveActivities.favoriteStartsToken"
    }
}
