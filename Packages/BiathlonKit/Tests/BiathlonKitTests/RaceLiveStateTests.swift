import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/live-activity.json` is shared with the server (`server/test`): the server
/// builds each state from its results and sends it as the Live Activity's
/// `content-state`, which ActivityKit decodes with a plain `JSONDecoder`, with its
/// `relevance-score`, which the app's local updates give as well.
struct RaceLiveStateTests {
    struct Case: CustomTestStringConvertible {
        let name: String
        let state: Data
        let relevanceScore: Double?
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "live-activity", withExtension: "json", subdirectory: "Fixtures")!
        let objects = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        return objects.map { object in
            let json = { (key: String) in
                try! JSONSerialization.data(withJSONObject: object[key]!, options: .fragmentsAllowed)
            }
            return Case(
                name: object["name"] as! String, state: json("state"),
                relevanceScore: object["relevanceScore"] as? Double)
        }
    }()

    /// As ActivityKit reads it: default decoding strategies.
    private static func decode(_ state: Data) throws -> RaceLiveState? {
        try JSONDecoder().decode(RaceLiveState?.self, from: state)
    }

    @Test(arguments: cases)
    func decodesTheServersState(_ example: Case) throws {
        let state = try Self.decode(example.state)
        #expect(state?.relevanceScore == example.relevanceScore)
    }

    @Test func roundTripsThroughDefaultCoding() throws {
        let state = try #require(Self.cases.compactMap { try? Self.decode($0.state) }.first)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RaceLiveState.self, from: data) == state)
    }

    @Test func activitiesOfLaterRacesWaitUntilShortlyBeforeTheStart() {
        let start = date("2026-11-26T15:15:00Z")
        #expect(
            RaceLiveState.activityStart(raceStart: start, now: date("2026-11-24T09:00:00Z"))
                == date("2026-11-26T14:45:00Z"))
        #expect(RaceLiveState.activityStart(raceStart: start, now: date("2026-11-26T15:00:00Z")) == nil)
        #expect(RaceLiveState.activityStart(raceStart: start, now: date("2026-11-26T15:30:00Z")) == nil)
    }

    @Test func aMovedRaceNeedsANewActivityWhereItsStartNoLongerFits() {
        let now = date("2026-11-26T09:00:00Z")
        let race = RaceLiveState(phase: .scheduled, startTime: date("2026-11-26T15:15:00Z"), leaders: [])
        let shownAt = date("2026-11-26T14:45:00Z")
        // Still on time.
        #expect(!race.needsNewActivity(scheduledStart: shownAt, isPending: true, now: now))
        // Moved: a pending activity would show at the old time.
        #expect(race.needsNewActivity(scheduledStart: date("2026-11-26T12:30:00Z"), isPending: true, now: now))
        // Postponed after the activity showed: it would run out before the new start.
        #expect(race.needsNewActivity(scheduledStart: nil, isPending: false, now: now))
        #expect(race.needsNewActivity(scheduledStart: date("2026-11-26T08:30:00Z"), isPending: false, now: now))
        // Brought forward to within the lead: a pending activity must show at once.
        let soon = date("2026-11-26T15:00:00Z")
        #expect(race.needsNewActivity(scheduledStart: date("2026-11-26T15:30:00Z"), isPending: true, now: soon))
        #expect(!race.needsNewActivity(scheduledStart: shownAt, isPending: false, now: soon))
        // A race that is over only ends its activity.
        var cancelled = race
        cancelled.phase = .cancelled
        #expect(!cancelled.needsNewActivity(scheduledStart: date("2026-11-26T12:30:00Z"), isPending: true, now: now))
    }

    @Test func onlyLiveAndUpcomingRacesCanBeFollowed() {
        #expect(Competition.State.allCases.filter(\.canBeFollowedLive) == [.scheduled, .live])
    }
}
