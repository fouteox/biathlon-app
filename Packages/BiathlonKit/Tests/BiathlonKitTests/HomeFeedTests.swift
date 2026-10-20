import Foundation
import Testing

@testable import BiathlonKit

struct HomeFeedTests {
    static let results = #"{"RaceId":"X","IsStartList":false,"IsResult":true,"Results":[]}"#

    @Test func featuresTheLiveRaceTheNextOneAndTheLatestResult() async throws {
        let client = stubClient([
            "Events?Level=1&SeasonId=2627": "["
                + event("E1", start: "2026-11-23T12:00:00Z", end: "2026-11-29T12:00:00Z") + ","
                + event("E2", start: "2026-12-01T12:00:00Z", end: "2026-12-07T12:00:00Z") + "]",
            "Competitions?EventId=E1": "["
                + race("E1-SP", start: "2026-11-26T15:00:00Z", status: 11, scheduleStatus: "FINISHED") + ","
                + race("E1-PU", start: "2026-11-27T11:00:00Z", isLive: true) + ","
                + race("E1-MS", start: "2026-11-28T14:00:00Z") + "]",
            "Competitions?EventId=E2": "[" + race("E2-SP", start: "2026-12-04T13:00:00Z") + "]",
            "Results?RaceId=E1-PU": Self.results,
            "Results?RaceId=E1-SP": Self.results,
        ])

        let feed = try await client.homeFeed(now: date("2026-11-27T11:30:00Z"))

        #expect(feed.live?.id == "E1-PU")
        #expect(feed.next?.id == "E1-MS")
        #expect(feed.latestFinished?.id == "E1-SP")
        #expect(feed.event?.id == "E1")
        #expect(feed.liveResults != nil)
        #expect(feed.latestResults != nil)
    }

    @Test func beforeTheSeasonFallsBackToThePreviousOne() async throws {
        let client = stubClient([
            "Events?Level=1&SeasonId=2627": "["
                + event("E1", start: "2026-11-23T12:00:00Z", end: "2026-11-29T12:00:00Z") + "]",
            "Events?Level=1&SeasonId=2526": "["
                + event("P8", start: "2026-03-09T12:00:00Z", end: "2026-03-15T12:00:00Z") + ","
                + event("P9", start: "2026-03-16T12:00:00Z", end: "2026-03-22T12:00:00Z") + "]",
            "Competitions?EventId=P9": "["
                + race("P9-MS", start: "2026-03-22T13:00:00Z", status: 11, scheduleStatus: "FINISHED") + "]",
            "Competitions?EventId=E1": "[" + race("E1-IN", start: "2026-11-26T15:15:00Z") + "]",
            "Results?RaceId=P9-MS": Self.results,
        ])

        let feed = try await client.homeFeed(now: date("2026-10-19T12:00:00Z"))

        #expect(feed.events.map(\.id) == ["P9", "E1"])
        #expect(feed.live == nil)
        #expect(feed.next?.id == "E1-IN")
        #expect(feed.latestFinished?.id == "P9-MS")
        #expect(feed.event?.id == "E1")
    }

    @Test func cancelledRacesAreNeverNext() throws {
        let feed = HomeFeed(
            events: [],
            races: [
                try decode(race("A", start: "2026-11-28T10:00:00Z", status: 6, scheduleStatus: "CANCELLED")),
                try decode(race("B", start: "2026-11-28T14:00:00Z")),
            ])
        #expect(feed.next?.id == "B")
    }

    @Test func isEmptyWithoutAnyRaceOrEvent() throws {
        let cancelled: Competition = try decode(
            race("A", start: "2026-11-28T10:00:00Z", status: 6, scheduleStatus: "CANCELLED"))
        let scheduled: Competition = try decode(race("B", start: "2026-11-28T14:00:00Z"))
        #expect(HomeFeed(events: [], races: []).isEmpty)
        #expect(HomeFeed(events: [], races: [cancelled]).isEmpty)
        #expect(!HomeFeed(events: [], races: [scheduled]).isEmpty)
    }
}
