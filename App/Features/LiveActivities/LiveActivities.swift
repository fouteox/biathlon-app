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

    /// Races with an activity on the Lock Screen or scheduled to show there, and races
    /// whose activity is being requested: a second tap meanwhile starts no duplicate.
    var followedRaceIDs: Set<String> { startedRaceIDs.union(requestedRaceIDs) }
    private var startedRaceIDs: Set<String> = []
    private var requestedRaceIDs: Set<String> = []
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

    /// Starts the race's activity on its broadcast channel, or schedules it to start
    /// shortly before a later race (`RaceLiveState.activityStart`).
    func follow(_ attributes: RaceActivityAttributes, state: RaceLiveState) async throws {
        guard !followedRaceIDs.contains(attributes.raceID) else { return }
        requestedRaceIDs.insert(attributes.raceID)
        defer {
            requestedRaceIDs.remove(attributes.raceID)
            refresh()
        }
        let channelID = try await channel(raceID: attributes.raceID)
        let content = ActivityContent(state: state, staleDate: nil)
        if let start = RaceLiveState.activityStart(raceStart: state.startTime, now: .now) {
            let minutes = Int(RaceLiveState.activityLead / 60)
            _ = try Activity.request(
                attributes: attributes, content: content, pushType: .channel(channelID), style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "Live Activity", body: "Starts in \(minutes) minutes", sound: .default),
                start: start)
        } else {
            _ = try Activity.request(attributes: attributes, content: content, pushType: .channel(channelID))
        }
    }

    /// Removes the race's activity from the Lock Screen at once.
    func stopFollowing(raceID: String) async {
        await Self.end(raceID: raceID)
        refresh()
    }

    // `Activity` isn't `Sendable` and its `update` and `end` run off the main actor:
    // the activities are looked up and changed off the main actor as well.

    /// Shows `state` in the race's activity, ending it once the race is over.
    @concurrent func update(raceID: String, with state: RaceLiveState) async {
        for activity in Self.activities(of: raceID) where activity.content.state != state {
            let content = ActivityContent(state: state, staleDate: nil)
            if state.phase.canBeFollowedLive {
                await activity.update(content)
            } else {
                await activity.end(content, dismissalPolicy: .default)
            }
        }
    }

    @concurrent private static func end(raceID: String) async {
        for activity in activities(of: raceID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func activities(of raceID: String) -> [Activity<RaceActivityAttributes>] {
        Activity<RaceActivityAttributes>.activities.filter { $0.attributes.raceID == raceID }
    }

    private func refresh() {
        startedRaceIDs = Set(
            Activity<RaceActivityAttributes>.activities
                .filter { [.pending, .active, .stale].contains($0.activityState) }
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
