import Foundation

/// The races the user turned on the Live Activity of ahead of time: the server starts each one
/// shortly before the race (`RaceLiveState.activityLead`, server/src/liveStarts.ts), like those
/// of the favorites' races.
public struct FollowedRaces: Codable, Equatable, Sendable {
    /// Each race's start when it was followed.
    private var starts: [String: Date] = [:]

    public init() {}

    /// A race is kept this long after the start it was followed with: a race postponed by less
    /// still starts its activity, and the server forgets its starts after as long.
    public static let retention: TimeInterval = 2 * 24 * 60 * 60

    public var raceIDs: [String] { starts.keys.sorted() }

    public var isEmpty: Bool { starts.isEmpty }

    public func contains(_ raceID: String) -> Bool { starts[raceID] != nil }

    public mutating func follow(_ raceID: String, startingAt start: Date) {
        starts[raceID] = start
    }

    public mutating func unfollow(_ raceID: String) {
        starts[raceID] = nil
    }

    /// Without the races that started more than `retention` before `now`.
    public func pruned(at now: Date) -> Self {
        var pruned = self
        pruned.starts = starts.filter { now < $0.value + Self.retention }
        return pruned
    }
}
