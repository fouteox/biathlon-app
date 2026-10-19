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

    /// `nil` when the response carries no `Competition` block.
    public init?(_ results: RaceResults) {
        guard let competition = results.competition else { return nil }
        phase = competition.state
        startTime = competition.startTime
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
