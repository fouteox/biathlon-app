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
        /// The race's activity is over.
        case ended(LiveActivityEnd)
    }

    /// Races with an activity on the Lock Screen or scheduled to show there, and races
    /// whose activity is being requested: a second tap meanwhile starts no duplicate.
    var followedRaceIDs: Set<String> { startedRaceIDs.union(requests.keys) }
    private var startedRaceIDs: Set<String> = []
    /// The request in flight for each race, which `stopFollowing` cancels.
    private var requests: [String: UUID] = [:]
    /// Whether the user allows Live Activities for the app (Settings).
    private(set) var areEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    @ObservationIgnored private let server: ServerClient?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    /// Each activity's observation, by activity identifier, until the activity ends.
    @ObservationIgnored private let activityObservers = KeyedTasks<String>()

    var isAvailable: Bool { server != nil && areEnabled }

    init(server: ServerClient?) {
        self.server = server
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
                    // One the server started for a favorite (LiveActivityStarts) may join one the
                    // app requested, and may have missed a broadcast during its start.
                    await self?.reconcile(raceID: activity.attributes.raceID)
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
        } catch let Failure.ended(end) {
            // The end was sent while the device was offline, which the channel doesn't keep.
            await Self.end(raceID: raceID, end)
        } catch Failure.noChannel {
            // A dropped channel the server hasn't replaced yet: looked up again at the next pass.
        } catch {
            Logger.notifications.error(
                "Reconciling the Live Activity failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Replaces the race's activities that no longer match its channel: the server opened
    /// a new one, or the race moved since the activity was scheduled
    /// (`RaceLiveState.needsNewActivity`), and ends all but one of those that match, the one
    /// on screen if any: the server can start one for a favorite's race the app requested
    /// an activity for. The replacement is requested first, so the race
    /// stays followed if it can't be, and only when no activity matches already, like one
    /// requested by a reconciliation the app was quit during; at the app's or the device's
    /// limit of activities, once the outdated ones have made room. The one kept gets the
    /// channel's state, for a broadcast it missed while the device was offline: the
    /// channel stores none. The update carries that broadcast's timestamp, for ActivityKit to
    /// ignore it once a newer broadcast arrived during the lookup. `true` when it requested a replacement.
    @discardableResult
    private func replaceOutdatedActivities(raceID: String) async throws -> Bool {
        guard let name = Self.activities(of: raceID).first?.attributes.name else { return false }
        var outdated: [String] = []
        var missed: [String] = []
        var latest: LiveChannel?
        var requested = false
        var full: LiveChannel?
        let checked = try await withChannel(raceID: raceID) { channel in
            let shown = Self.activities(of: raceID).filter { Self.shownStates.contains($0.activityState) }
            let isCurrent = { (activity: Activity<RaceActivityAttributes>) in
                activity.attributes.channelID == channel.id
                    && !channel.state.needsNewActivity(
                        scheduledStart: activity.attributes.scheduledStart,
                        isPending: activity.activityState == .pending, now: .now)
            }
            let current = shown.filter(isCurrent)
            let kept = current.first { $0.activityState == .active } ?? current.first
            outdated = shown.filter { $0.id != kept?.id }.map(\.id)
            if let kept, kept.content.state != channel.state { missed = [kept.id] }
            latest = channel
            if !outdated.isEmpty && kept == nil {
                do {
                    try Self.request(raceID: raceID, name: name, on: channel)
                    requested = true
                } catch ActivityAuthorizationError.targetMaximumExceeded,
                    ActivityAuthorizationError.globalMaximumExceeded
                {
                    full = channel
                }
            }
        }
        guard checked else { return false }
        if let latest, !missed.isEmpty {
            await Self.update(
                raceID: raceID, activityIDs: missed, state: latest.state,
                timestamp: Date(timeIntervalSince1970: latest.timestamp))
        }
        if let full {
            // Still requested while they end, the race stays followed.
            return try await whileRequested(raceID: raceID) { isCurrent in
                for activityID in outdated { await Self.end(raceID: raceID, activityID: activityID) }
                guard isCurrent() else { return false }
                try Self.request(raceID: raceID, name: name, on: full)
                return true
            }
        }
        for activityID in outdated { await Self.end(raceID: raceID, activityID: activityID) }
        refresh()
        return requested
    }

    /// Runs `body` with the race's channel, unless `stopFollowing` cancels the request
    /// during the lookup; `false` then.
    @discardableResult
    private func withChannel(raceID: String, _ body: (LiveChannel) throws -> Void) async throws -> Bool {
        try await whileRequested(raceID: raceID) { isCurrent in
            let channel = try await self.channel(raceID: raceID)
            guard isCurrent() else { return false }
            try body(channel)
            return true
        }
    }

    /// Runs `work` as the race's request in flight, which `stopFollowing` cancels: `work`
    /// checks `isCurrent` after each suspension, before it requests an activity.
    private func whileRequested(
        raceID: String, _ work: (_ isCurrent: () -> Bool) async throws -> Bool
    ) async throws -> Bool {
        let request = UUID()
        requests[raceID] = request
        defer {
            if requests[raceID] == request { requests[raceID] = nil }
            refresh()
        }
        return try await work { self.requests[raceID] == request }
    }

    /// Requests the race's activity on `channel`, from the state last published on it:
    /// the channel stores no messages, and the app's cached results could lag behind.
    private static func request(raceID: String, name: String, on channel: LiveChannel) throws {
        try request(raceID: raceID, name: name, channelID: channel.id, state: channel.state)
    }

    /// Requests the race's activity on the channel `channelID`, showing `state`.
    static func request(raceID: String, name: String, channelID: String, state: RaceLiveState) throws {
        let start = RaceLiveState.activityStart(raceStart: state.startTime, now: .now)
        let attributes = RaceActivityAttributes(
            raceID: raceID, name: name, channelID: channelID, scheduledStart: start)
        let content = state.activityContent
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

    // `Activity` isn't `Sendable` and its `update` and `end` run off the main actor: the
    // activities are looked up, updated and ended off the main actor as well.

    /// Shows `state`, published at `timestamp`, on the race's activities, or only `activityIDs`.
    @concurrent static func update(
        raceID: String, activityIDs: [String]? = nil, state: RaceLiveState, timestamp: Date
    ) async {
        let content = state.activityContent
        for activity in activities(of: raceID) where activityIDs?.contains(activity.id) ?? true {
            await activity.update(content, timestamp: timestamp)
        }
    }

    /// Ends the race's activities, or only `activityID`: showing the final state of `end` until
    /// its dismissal date, like the server's end event, or removing them at once without it.
    @concurrent static func end(raceID: String, activityID: String? = nil, _ end: LiveActivityEnd? = nil) async {
        let content = end?.finalState.activityContent
        let dismissalPolicy = end.map { ActivityUIDismissalPolicy.after($0.dismissalDate) } ?? .immediate
        for activity in activities(of: raceID) where activityID == nil || activity.id == activityID {
            await activity.end(content, dismissalPolicy: dismissalPolicy)
        }
    }

    private nonisolated static func activities(of raceID: String) -> [Activity<RaceActivityAttributes>] {
        Activity<RaceActivityAttributes>.activities.filter { $0.attributes.raceID == raceID }
    }

    /// The server's cron runs every minute.
    private static let channelLookupInterval = Duration.seconds(60)

    /// Activities on screen or scheduled to show.
    static let shownStates: [ActivityState] = [.pending, .active, .stale]

    private func refresh() {
        startedRaceIDs = Set(
            Activity<RaceActivityAttributes>.activities
                .filter { Self.shownStates.contains($0.activityState) }
                .map(\.attributes.raceID))
    }

    /// Ended and dismissed activities leave `followedRaceIDs`, wherever they end, and a
    /// broadcast that moves the race reschedules its activity while the app runs. The
    /// observation stops once the activity ends: it won't update its content anymore.
    private func observeState(of activity: Activity<RaceActivityAttributes>) {
        let raceID = activity.attributes.raceID
        let scheduledStart = activity.attributes.scheduledStart
        activityObservers.run(
            activity.id,
            { [weak self] in
                for await state in activity.activityStateUpdates {
                    self?.refresh()
                    guard Self.shownStates.contains(state) else { return }
                }
            },
            { [weak self] in
                for await content in activity.contentUpdates
                where content.state.needsNewActivity(
                    scheduledStart: scheduledStart, isPending: activity.activityState == .pending, now: .now)
                {
                    await self?.reconcile(raceID: raceID)
                }
            })
    }

    private func channel(raceID: String) async throws -> LiveChannel {
        guard let server else { throw Failure.noChannel }
        switch try await server.liveChannel(raceID: raceID, environment: .current) {
        case .open(let channel): return channel
        case .notOpen: throw Failure.noChannel
        case .ended(let end): throw Failure.ended(end)
        }
    }
}

extension RaceLiveState {
    /// The activity's content, ranked like the server's broadcasts.
    nonisolated var activityContent: ActivityContent<RaceLiveState> {
        ActivityContent(state: self, staleDate: nil, relevanceScore: relevanceScore)
    }
}
