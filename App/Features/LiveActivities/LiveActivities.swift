import ActivityKit
import BiathlonKit
import Foundation
import Observation

/// Starts, updates and ends the races' Live Activities.
///
/// An activity subscribes to its race's APNs broadcast channel, which the server opens
/// for upcoming races and publishes each new state on. While a race is on screen, the
/// app also updates its activity itself, as Apple recommends: a device may miss pushes.
@Observable
final class LiveActivities {
    enum Failure: Error {
        /// The server has no channel for the race yet.
        case noChannel
        case server(status: Int)
    }

    /// Races with an activity on the Lock Screen.
    private(set) var followedRaceIDs: Set<String> = []
    /// Whether the user allows Live Activities for the app (Settings).
    private(set) var areEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    @ObservationIgnored private let serverURL = Bundle.main.serverURL
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    var isAvailable: Bool { serverURL != nil && areEnabled }

    init() {
        refresh()
        observers = [
            Task { [weak self] in
                for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                    self?.areEnabled = enabled
                }
            },
            Task { [weak self] in
                for await activity in Activity<RaceActivityAttributes>.activityUpdates {
                    self?.refresh()
                    self?.observeState(of: activity)
                }
            },
        ]
        for activity in Activity<RaceActivityAttributes>.activities { observeState(of: activity) }
    }

    isolated deinit {
        for observer in observers { observer.cancel() }
    }

    /// Starts the race's activity on its broadcast channel.
    func follow(_ attributes: RaceActivityAttributes, state: RaceLiveState) async throws {
        guard !followedRaceIDs.contains(attributes.raceID) else { return }
        let channelID = try await channel(raceID: attributes.raceID)
        _ = try Activity.request(
            attributes: attributes, content: ActivityContent(state: state, staleDate: nil),
            pushType: .channel(channelID))
        refresh()
    }

    /// Removes the race's activity from the Lock Screen at once.
    func stopFollowing(raceID: String) async {
        for activity in activities(of: raceID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        refresh()
    }

    /// Shows `state` in the race's activity, ending it once the race is over.
    func update(raceID: String, with state: RaceLiveState) async {
        for activity in activities(of: raceID) where activity.content.state != state {
            let content = ActivityContent(state: state, staleDate: nil)
            if state.phase.canBeFollowedLive {
                await activity.update(content)
            } else {
                await activity.end(content, dismissalPolicy: .default)
            }
        }
    }

    private func activities(of raceID: String) -> [Activity<RaceActivityAttributes>] {
        Activity<RaceActivityAttributes>.activities.filter { $0.attributes.raceID == raceID }
    }

    private func refresh() {
        followedRaceIDs = Set(
            Activity<RaceActivityAttributes>.activities
                .filter { $0.activityState == .active || $0.activityState == .stale }
                .map(\.attributes.raceID))
    }

    /// Ended and dismissed activities leave `followedRaceIDs`, wherever they end.
    private func observeState(of activity: Activity<RaceActivityAttributes>) {
        observers.append(
            Task { [weak self] in
                for await _ in activity.activityStateUpdates { self?.refresh() }
            })
    }

    private func channel(raceID: String) async throws -> String {
        guard let serverURL else { throw Failure.noChannel }
        let url = serverURL.appending(path: "v1/races/\(raceID)/channels/\(APNsEnvironment.current.rawValue)")
        let (data, response) = try await URLSession.shared.data(from: url)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try JSONDecoder().decode(Channel.self, from: data).channelId
        case 404: throw Failure.noChannel
        case let status: throw Failure.server(status: status ?? 0)
        }
    }

    private struct Channel: Decodable {
        let channelId: String
    }
}
