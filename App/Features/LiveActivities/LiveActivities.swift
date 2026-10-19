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
    var followedRaceIDs: Set<String> { startedRaceIDs.union(requests.keys) }
    private var startedRaceIDs: Set<String> = []
    /// The request in flight for each race, which `stopFollowing` cancels.
    private var requests: [String: UUID] = [:]
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
    func follow(raceID: String, name: String, state: RaceLiveState) async throws {
        guard !followedRaceIDs.contains(raceID) else { return }
        let request = UUID()
        requests[raceID] = request
        defer {
            if requests[raceID] == request { requests[raceID] = nil }
            refresh()
        }
        let channelID = try await channel(raceID: raceID)
        // Turned off meanwhile.
        guard requests[raceID] == request else { return }
        let start = RaceLiveState.activityStart(raceStart: state.startTime, now: .now)
        let attributes = RaceActivityAttributes(raceID: raceID, name: name, scheduledStart: start)
        let content = ActivityContent(state: state, staleDate: nil)
        if let start {
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

    /// Removes the race's activity from the Lock Screen at once, or cancels its request.
    func stopFollowing(raceID: String) async {
        requests[raceID] = nil
        await Self.end(raceID: raceID)
        refresh()
    }

    /// Shows `state` in the race's activity, ending it once the race is over. A scheduled
    /// activity whose race moved is scheduled again at the new time.
    func update(raceID: String, with state: RaceLiveState) async throws {
        let start = RaceLiveState.activityStart(raceStart: state.startTime, now: .now)
        let moved = Self.activities(of: raceID).first {
            $0.activityState == .pending && $0.attributes.scheduledStart != start
        }
        if let moved {
            let name = moved.attributes.name
            await stopFollowing(raceID: raceID)
            try await follow(raceID: raceID, name: name, state: state)
        } else {
            await Self.update(raceID: raceID, with: state)
        }
    }

    // `Activity` isn't `Sendable` and its `update` and `end` run off the main actor:
    // the activities are looked up and changed off the main actor as well.

    @concurrent private static func update(raceID: String, with state: RaceLiveState) async {
        for activity in activities(of: raceID) where activity.content.state != state {
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
