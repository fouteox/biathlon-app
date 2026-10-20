import Foundation

/// What a race's Live Activity shows.
///
/// It is the Live Activity's `ContentState`: the server builds it from the calendar and
/// `Results?RaceId=` (`server/src/live.ts`) and sends it as the push payload's
/// `content-state`, which ActivityKit decodes with the default `Codable` strategies
/// (a `Date` is seconds since 2001-01-01), checked against the shared `live-activity.json` fixture.
public struct RaceLiveState: Codable, Hashable, Sendable {
    public var phase: Competition.State
    public var startTime: Date
    /// The first ranked rows, at most three (`LEADER_COUNT` on the server).
    public var leaders: [Leader]

    public struct Leader: Codable, Hashable, Sendable {
        public var rank: String
        public var name: String
        public var nation: String?
        /// The leader's time, then each follower's gap to them.
        public var result: String?
    }
}

extension RaceLiveState {
    /// Activities show from this long before the start: ActivityKit ends a standard
    /// Live Activity after eight hours, so one started days ahead would end before the race.
    public static let activityLead: TimeInterval = 30 * 60

    /// When to start the activity of a race starting at `raceStart`; `nil` for now.
    public static func activityStart(raceStart: Date, now: Date) -> Date? {
        let start = raceStart - activityLead
        return start > now ? start : nil
    }

    /// Whether an activity shown from `scheduledStart` (`nil`: at once) must be requested
    /// again, ActivityKit being unable to move its start: a pending one whose race moved,
    /// or one already shown for a race postponed beyond the lead.
    public func needsNewActivity(scheduledStart: Date?, isPending: Bool, now: Date) -> Bool {
        guard phase.canBeFollowedLive else { return false }
        let start = Self.activityStart(raceStart: startTime, now: now)
        return start != scheduledStart && (start != nil || isPending)
    }
}

extension RaceLiveState {
    /// The `relevance-score` of the server's broadcasts (`relevanceScore` in `server/src/live.ts`),
    /// for the app's own updates: with several races followed, the Dynamic Island shows the
    /// live one rather than the first activity started. Upcoming races rank alike: their
    /// activities only show from `activityLead` before the start, and races are farther apart.
    /// Between 0 and 1, as the server explains.
    public var relevanceScore: Double {
        switch phase {
        case .live: 1
        case .scheduled: 0.5
        case .finished, .cancelled: 0
        }
    }
}

extension Competition.State {
    /// A Live Activity follows a race until it ends.
    public var canBeFollowedLive: Bool { self == .scheduled || self == .live }
}

#if DEBUG
    extension RaceLiveState {
        /// A race starting at `startTime`, from its start list to its result, then cancelled
        /// instead: every state its Live Activity shows, for trying it without a race in Xcode
        /// previews and the app's developer settings.
        public static func demo(startTime: Date) -> [RaceLiveState] {
            let firstPodium = [
                Leader(rank: "1", name: "PERROT E.", nation: "FRA", result: "12:41.6"),
                Leader(rank: "2", name: "LAEGREID S.", nation: "NOR", result: "+4.2"),
                Leader(rank: "3", name: "SAMUELSSON S.", nation: "SWE", result: "+9.8"),
            ]
            let finalPodium = [
                Leader(rank: "1", name: "JACQUELIN E.", nation: "FRA", result: "24:58.3"),
                Leader(rank: "2", name: "PERROT E.", nation: "FRA", result: "+2.1"),
                Leader(rank: "3", name: "LAEGREID S.", nation: "NOR", result: "+6.4"),
            ]
            return [
                RaceLiveState(phase: .scheduled, startTime: startTime, leaders: []),
                RaceLiveState(phase: .live, startTime: startTime, leaders: []),
                RaceLiveState(phase: .live, startTime: startTime, leaders: firstPodium),
                RaceLiveState(phase: .live, startTime: startTime, leaders: finalPodium),
                RaceLiveState(phase: .finished, startTime: startTime, leaders: finalPodium),
                RaceLiveState(phase: .cancelled, startTime: startTime, leaders: []),
            ]
        }
    }
#endif
