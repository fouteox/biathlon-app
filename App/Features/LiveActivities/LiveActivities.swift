import ActivityKit
import BiathlonKit
import Foundation
import Observation
import os

/// Starts, updates and ends the races' Live Activities.
///
/// An activity subscribes to its race's APNs broadcast channel, which the server opens
/// for upcoming races and publishes each new state on. The server is the only source of
/// the activity's content: the app's cached results could be older than a push.
@Observable
final class LiveActivities {
    enum Failure: Error, Equatable {
        /// The server has no channel for the race yet.
        case noChannel
        /// The race's activity is over, with its final state.
        case ended(RaceLiveState)
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
    func follow(raceID: String, name: String) async throws {
        guard !followedRaceIDs.contains(raceID) else { return }
        let requested = try await withChannel(raceID: raceID) { try Self.request(raceID: raceID, name: name, on: $0) }
        if requested { await reconcile(raceID: raceID) }
    }

    /// Removes the race's activity from the Lock Screen at once, or cancels its request.
    func stopFollowing(raceID: String) async {
        requests[raceID] = nil
        await Self.end(raceID: raceID)
        refresh()
    }

    /// Brings every followed race's activities in line with their channels while the app is
    /// in the foreground, until cancelled: a broadcast can update an activity but can't move
    /// its scheduled start or subscribe it to the channel the server opens in place of one
    /// APNs dropped, and a lookup the network or the server failed is tried again.
    func reconcileWhileActive() async {
        while !Task.isCancelled {
            for raceID in startedRaceIDs { await reconcile(raceID: raceID) }
            try? await Task.sleep(for: Self.channelLookupInterval)
        }
    }

    /// A new activity subscribes after the channel lookup: whatever the server sent in
    /// between, the end above all, is missed, the channel storing no messages. A second
    /// lookup once subscribed catches it.
    private func reconcile(raceID: String) async {
        do {
            if try await replaceOutdatedActivities(raceID: raceID) {
                try await replaceOutdatedActivities(raceID: raceID)
            }
        } catch let Failure.ended(finalState) {
            // The end was sent while the device was offline, which the channel doesn't keep.
            await Self.end(raceID: raceID, finalState: finalState)
        } catch Failure.noChannel {
            // A dropped channel the server hasn't replaced yet: looked up again at the next pass.
        } catch {
            Logger.notifications.error(
                "Reconciling the Live Activity failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Replaces the race's activities that no longer match its channel: the server opened
    /// a new one, or the race moved since the activity was scheduled
    /// (`RaceLiveState.needsNewActivity`). The replacement is requested first, so the race
    /// stays followed if it can't be, and only when no activity matches already, like one
    /// requested by a reconciliation the app was quit during. The current ones get the
    /// channel's state, for a broadcast they missed while the device was offline: the
    /// channel stores none. The update carries that broadcast's timestamp, for ActivityKit to
    /// ignore it once a newer broadcast arrived during the lookup. `true` when it requested a replacement.
    @discardableResult
    private func replaceOutdatedActivities(raceID: String) async throws -> Bool {
        guard let name = Self.activities(of: raceID).first?.attributes.name else { return false }
        var outdated: [String] = []
        var missed: [String] = []
        var latest: Channel?
        var requested = false
        let checked = try await withChannel(raceID: raceID) { channel in
            let shown = Self.activities(of: raceID).filter { Self.shownStates.contains($0.activityState) }
            let isCurrent = { (activity: Activity<RaceActivityAttributes>) in
                activity.attributes.channelID == channel.channelId
                    && !channel.state.needsNewActivity(
                        scheduledStart: activity.attributes.scheduledStart,
                        isPending: activity.activityState == .pending, now: .now)
            }
            outdated = shown.filter { !isCurrent($0) }.map(\.id)
            missed = shown.filter { isCurrent($0) && $0.content.state != channel.state }.map(\.id)
            latest = channel
            if !outdated.isEmpty && !shown.contains(where: isCurrent) {
                try Self.request(raceID: raceID, name: name, on: channel)
                requested = true
            }
        }
        guard checked else { return false }
        if let latest, !missed.isEmpty {
            await Self.update(
                raceID: raceID, activityIDs: missed, state: latest.state,
                timestamp: Date(timeIntervalSince1970: latest.timestamp))
        }
        for activityID in outdated { await Self.end(raceID: raceID, activityID: activityID) }
        refresh()
        return requested
    }

    /// Runs `body` with the race's channel, unless `stopFollowing` cancels the request
    /// during the lookup; `false` then.
    @discardableResult
    private func withChannel(raceID: String, _ body: (Channel) throws -> Void) async throws -> Bool {
        let request = UUID()
        requests[raceID] = request
        defer {
            if requests[raceID] == request { requests[raceID] = nil }
            refresh()
        }
        let channel = try await channel(raceID: raceID)
        guard requests[raceID] == request else { return false }
        try body(channel)
        return true
    }

    /// Requests the race's activity on `channel`, from the state last published on it:
    /// the channel stores no messages, and the app's cached results could lag behind.
    private static func request(raceID: String, name: String, on channel: Channel) throws {
        let start = RaceLiveState.activityStart(raceStart: channel.state.startTime, now: .now)
        let attributes = RaceActivityAttributes(
            raceID: raceID, name: name, channelID: channel.channelId, scheduledStart: start)
        let content = ActivityContent(state: channel.state, staleDate: nil)
        if let start {
            let minutes = Int(RaceLiveState.activityLead / 60)
            _ = try Activity.request(
                attributes: attributes, content: content, pushType: .channel(channel.channelId), style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "Live Activity", body: "Starts in \(minutes) minutes", sound: .default),
                start: start)
        } else {
            _ = try Activity.request(attributes: attributes, content: content, pushType: .channel(channel.channelId))
        }
    }

    // `Activity` isn't `Sendable` and its `update` and `end` run off the main actor: the
    // activities are looked up, updated and ended off the main actor as well.

    /// Shows `state`, published at `timestamp`, on the race's activities `activityIDs`.
    @concurrent private static func update(
        raceID: String, activityIDs: [String], state: RaceLiveState, timestamp: Date
    ) async {
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in activities(of: raceID) where activityIDs.contains(activity.id) {
            await activity.update(content, timestamp: timestamp)
        }
    }

    /// Ends the race's activities, or only `activityID`: showing `finalState` until the system
    /// dismisses them, like the server's end event, or removing them at once without it.
    @concurrent private static func end(
        raceID: String, activityID: String? = nil, finalState: RaceLiveState? = nil
    ) async {
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        for activity in activities(of: raceID) where activityID == nil || activity.id == activityID {
            await activity.end(content, dismissalPolicy: content == nil ? .immediate : .default)
        }
    }

    private nonisolated static func activities(of raceID: String) -> [Activity<RaceActivityAttributes>] {
        Activity<RaceActivityAttributes>.activities.filter { $0.attributes.raceID == raceID }
    }

    /// The server's cron runs every minute.
    private static let channelLookupInterval = Duration.seconds(60)

    /// Activities on screen or scheduled to show.
    private static let shownStates: [ActivityState] = [.pending, .active, .stale]

    private func refresh() {
        startedRaceIDs = Set(
            Activity<RaceActivityAttributes>.activities
                .filter { Self.shownStates.contains($0.activityState) }
                .map(\.attributes.raceID))
    }

    /// Ended and dismissed activities leave `followedRaceIDs`, wherever they end, and a
    /// broadcast that moves the race reschedules its activity while the app runs.
    private func observeState(of activity: Activity<RaceActivityAttributes>) {
        let raceID = activity.attributes.raceID
        let scheduledStart = activity.attributes.scheduledStart
        observers.append(contentsOf: [
            Task { [weak self] in
                for await _ in activity.activityStateUpdates { self?.refresh() }
            },
            Task { [weak self] in
                for await content in activity.contentUpdates
                where content.state.needsNewActivity(
                    scheduledStart: scheduledStart, isPending: activity.activityState == .pending, now: .now)
                {
                    await self?.reconcile(raceID: raceID)
                }
            },
        ])
    }

    private func channel(raceID: String) async throws -> Channel {
        guard let serverURL else { throw Failure.noChannel }
        let url = serverURL.appending(path: "v1/races/\(raceID)/channels/\(APNsEnvironment.current.rawValue)")
        let (data, response) = try await URLSession.shared.data(from: url)
        switch (response as? HTTPURLResponse)?.statusCode {
        // Default strategies, like ActivityKit's for the `content-state` of the broadcasts.
        case 200: return try JSONDecoder().decode(Channel.self, from: data)
        case 404: throw Failure.noChannel
        case 410: throw Failure.ended(try JSONDecoder().decode(Ended.self, from: data).state)
        case let status: throw Failure.server(status: status ?? 0)
        }
    }

    private struct Channel: Decodable {
        let channelId: String
        let state: RaceLiveState
        /// The `timestamp` of the broadcast that published `state`, in seconds since 1970 like
        /// that of an ActivityKit push.
        let timestamp: TimeInterval
    }

    private struct Ended: Decodable {
        let state: RaceLiveState
    }
}
