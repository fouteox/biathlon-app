import Foundation
import Testing

@testable import BiathlonKit

/// `Fixtures/live-activity.json` is shared with the server (`server/test`): the server
/// builds each state from its results and sends it as the Live Activity's
/// `content-state`, which ActivityKit decodes with a plain `JSONDecoder`, with its
/// `relevance-score`, which the app's local updates give as well.
struct RaceLiveStateTests {
    struct Case: Decodable, CustomTestStringConvertible {
        let name: String
        let state: RaceLiveState?
        let relevanceScore: Double?
        var testDescription: String { name }
    }

    /// As ActivityKit reads a `content-state`: default decoding strategies.
    static func cases() throws -> [Case] {
        let url = try #require(
            Bundle.module.url(forResource: "live-activity", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test(arguments: try cases())
    func decodesTheServersState(_ example: Case) {
        #expect(example.state?.relevanceScore == example.relevanceScore)
    }

    @Test func roundTripsThroughDefaultCoding() throws {
        let state = try #require(Self.cases().compactMap(\.state).first)
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
    }

    /// A race that is over only ends its activity, even one waiting to show at an old start.
    @Test(arguments: [Competition.State.finished, .cancelled])
    func anEndedRaceNeverNeedsANewActivity(phase: Competition.State) {
        let now = date("2026-11-26T09:00:00Z")
        let race = RaceLiveState(phase: phase, startTime: date("2026-11-26T15:15:00Z"), leaders: [])
        #expect(!race.needsNewActivity(scheduledStart: date("2026-11-26T12:30:00Z"), isPending: true, now: now))
        #expect(!race.needsNewActivity(scheduledStart: nil, isPending: false, now: now))
    }
}
