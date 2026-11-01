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

    /// The live race, otherwise the next one: what the widget shows and Siri tells.
    public var upcomingRace: Competition? { live ?? next }

    /// When the widget reloads, within WidgetKit's budget of a reload every 15 to 60 minutes
    /// or so: every 15 minutes while a race is live, at the next race's start, otherwise every
    /// hour, which also catches a start moved. Never sooner than WidgetKit's 5 minutes, for a
    /// start already past that the race hasn't gone live at.
    public func widgetReloadDate(now: Date) -> Date {
        if live != nil { return now + Self.widgetLiveInterval }
        let latest = now + Self.widgetInterval
        guard let next else { return latest }
        return min(max(next.startTime, now + Self.widgetMinimumInterval), latest)
    }

    /// When the app, open before a race with none live, fetches the feed again so the live race
    /// shows by itself: at the next race's start, then every minute, as the IBU marks a race
    /// live a little after its start. `nil` while a race is live, which the app polls, and with
    /// no race ahead.
    public func nextStartRefreshDate(now: Date) -> Date? {
        guard live == nil, let next else { return nil }
        return max(next.startTime, now + Self.lateStartInterval)
    }

    public static let lateStartInterval: TimeInterval = 60
    public static let widgetLiveInterval: TimeInterval = 15 * 60
    public static let widgetInterval: TimeInterval = 60 * 60
    public static let widgetMinimumInterval: TimeInterval = 5 * 60

    /// Event of the featured race.
    public var event: BiathlonEvent? {
        guard let race = live ?? next ?? latestFinished else { return events.last }
        return event(of: race) ?? events.last
    }

    /// A race's event (a `RaceId` starts with its `EventId`): between two events, the latest
    /// result belongs to the previous one.
    public func event(of race: Competition) -> BiathlonEvent? {
        events.first { race.id.hasPrefix($0.id) }
    }

    /// Nothing to feature: no race to show and no event to open.
    public var isEmpty: Bool {
        live == nil && next == nil && latestFinished == nil && event == nil
    }
}

extension IBUClient {
    /// The races of the most recent event already started and of the next one, without
    /// their results: what the widget needs.
    public func featuredRaces(now: Date) async throws -> HomeFeed {
        let season = SeasonID.containing(now)
        let events = try await self.events(season: season).sorted { $0.startDate < $1.startDate }
        let upcoming = events.first { $0.startDate > now }
        var started = events.last { $0.startDate <= now }
        // Before the first event of a season: the latest result of the previous one.
        if started == nil {
            started = try await self.events(season: season.previous).max { $0.startDate < $1.startDate }
        }
        let featured = [started, upcoming].compactMap(\.self)
        return HomeFeed(events: featured, races: try await competitions(of: featured))
    }

    /// The featured races and the results of the live one and of the latest finished one.
    public func homeFeed(now: Date) async throws -> HomeFeed {
        var feed = try await featuredRaces(now: now)
        let (live, finished) = (feed.live, feed.latestFinished)
        async let liveResults = results(of: live)
        async let latestResults = results(of: finished)
        (feed.liveResults, feed.latestResults) = try await (liveResults, latestResults)
        return feed
    }
}
