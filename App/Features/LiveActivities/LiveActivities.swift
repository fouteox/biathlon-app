import ActivityKit
import BiathlonKit
import Foundation
import Observation

/// Starts, updates and ends the races' Live Activities.
///
/// An activity subscribes to its race's APNs broadcast channel, which the server opens
/// for upcoming races and publishes each new state on. The server is the only source of
/// the activity's content: the app's cached results could be older than a push.
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
        try await start(raceID: raceID, name: name, state: state)
    }

    /// Removes the race's activity from the Lock Screen at once, or cancels its request.
    func stopFollowing(raceID: String) async {
        requests[raceID] = nil
        await Self.end(raceID: raceID)
        refresh()
    }

    /// Requests a new activity for a race that moved since its activity was scheduled
    /// (`RaceLiveState.needsNewActivity`), then ends the old one.
    func reschedule(raceID: String, for state: RaceLiveState) async throws {
        let moved = Self.activities(of: raceID).first {
            Self.shownStates.contains($0.activityState)
                && state.needsNewActivity(
                    scheduledStart: $0.attributes.scheduledStart, isPending: $0.activityState == .pending, now: .now)
        }
        guard let moved else { return }
        let (movedID, name) = (moved.id, moved.attributes.name)
        // The replacement first: the race stays followed if it can't be scheduled.
        guard try await start(raceID: raceID, name: name, state: state) else { return }
        await Self.end(raceID: raceID, activityID: movedID)
        refresh()
    }

    /// Requests the race's activity on its channel; `false` when `stopFollowing` cancels
    /// the request meanwhile.
    @discardableResult
    private func start(raceID: String, name: String, state: RaceLiveState) async throws -> Bool {
        let request = UUID()
        requests[raceID] = request
        defer {
            if requests[raceID] == request { requests[raceID] = nil }
            refresh()
        }
        let channelID = try await channel(raceID: raceID)
        guard requests[raceID] == request else { return false }
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
        return true
    }

    // `Activity` isn't `Sendable` and its `end` runs off the main actor: the activities
    // are looked up and ended off the main actor as well.

    /// Ends the race's activities, or only `activityID`.
    @concurrent private static func end(raceID: String, activityID: String? = nil) async {
        for activity in activities(of: raceID) where activityID == nil || activity.id == activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func activities(of raceID: String) -> [Activity<RaceActivityAttributes>] {
        Activity<RaceActivityAttributes>.activities.filter { $0.attributes.raceID == raceID }
    }

    /// Activities on screen or scheduled to show.
    private static let shownStates: [ActivityState] = [.pending, .active, .stale]

    private func refresh() {
        startedRaceIDs = Set(
            Activity<RaceActivityAttributes>.activities
                .filter { Self.shownStates.contains($0.activityState) }
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
