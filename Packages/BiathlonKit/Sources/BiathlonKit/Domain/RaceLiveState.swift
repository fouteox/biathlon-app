import Foundation

/// What a race's Live Activity shows, built from `Results?RaceId=`.
///
/// It is the Live Activity's `ContentState`: the server sends it as the push payload's
/// `content-state`, which ActivityKit decodes with the default `Codable` strategies
/// (a `Date` is seconds since 2001-01-01). The server builds it with the same rules
/// (`server/src/live.ts`), checked against the shared `live-activity.json` fixture.
public struct RaceLiveState: Codable, Hashable, Sendable {
    public var phase: Competition.State
    public var startTime: Date
    /// The first ranked rows, at most `leaderCount`.
    public var leaders: [Leader]

    public static let leaderCount = 3

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

    /// A race nobody has results for yet, from the calendar alone (`calendarState` on the server).
    public init(race: Competition) {
        self.init(phase: race.state, startTime: race.startTime, leaders: [])
    }

    /// `nil` when the response carries no `Competition` block.
    public init?(_ results: RaceResults) {
        guard let competition = results.competition else { return nil }
        self.init(race: competition)
        let ranked = results.standings
            .filter { $0.irm == nil }
            .compactMap { row in row.rank.map { (row: row, rank: $0) } }
            .prefix(Self.leaderCount)
        leaders = ranked.enumerated().map { index, entry in
            Leader(
                rank: entry.rank,
                name: entry.row.shortName ?? entry.row.name,
                nation: entry.row.nation,
                result: index == 0 ? entry.row.totalTime : entry.row.behind)
        }
    }
}

extension Competition.State {
    /// A Live Activity follows a race until it ends.
    public var canBeFollowedLive: Bool { self == .scheduled || self == .live }
}
