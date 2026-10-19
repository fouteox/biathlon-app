import Foundation

/// What the home screen shows: the live race if there is one, otherwise the
/// next one, plus the latest results.
public struct HomeFeed: Sendable {
    /// The most recent event already started and the next one: a race can
    /// finish after its event's `EndDate`, and between two events both the
    /// latest result and the next race are needed.
    public let events: [BiathlonEvent]
    /// Races of `events`, by start time.
    public let races: [Competition]
    public var liveResults: RaceResults?
    public var latestResults: RaceResults?

    public init(events: [BiathlonEvent], races: [Competition]) {
        self.events = events
        self.races = races.sorted { $0.startTime < $1.startTime }
    }

    public var live: Competition? { races.first { $0.state == .live } }
    public var next: Competition? { races.first { $0.state == .scheduled } }
    public var latestFinished: Competition? { races.last { $0.state == .finished } }

    /// Event of the featured race (a `RaceId` starts with its `EventId`).
    public var event: BiathlonEvent? {
        guard let race = live ?? next ?? latestFinished else { return events.last }
        return events.first { race.id.hasPrefix($0.id) } ?? events.last
    }
}

extension IBUClient {
    public func homeFeed(now: Date) async throws -> HomeFeed {
        let season = SeasonID.containing(now)
        let events = try await self.events(season: season).sorted { $0.startDate < $1.startDate }
        let upcoming = events.first { $0.startDate > now }
        var started = events.last { $0.startDate <= now }
        // Before the first event of a season: the latest result of the previous one.
        if started == nil {
            started = try await self.events(season: season.previous).max { $0.startDate < $1.startDate }
        }
        let featured = [started, upcoming].compactMap(\.self)

        var races: [Competition] = []
        for event in featured {
            races += try await competitions(eventID: event.id)
        }
        var feed = HomeFeed(events: featured, races: races)
        if let live = feed.live {
            feed.liveResults = try await results(raceID: live.id)
        }
        if let finished = feed.latestFinished {
            feed.latestResults = try await results(raceID: finished.id)
        }
        return feed
    }
}
