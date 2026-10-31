import BiathlonKit
import Foundation
import Testing

@testable import Biathlon

/// What Siri says, on the sample World Cup: the men's pursuit in Nordvik is over, the women's is next.
struct SiriAnswerTests {
    private static let now = try! Date("2026-12-05T13:00:00Z", strategy: .iso8601)

    private static func feed() async throws -> HomeFeed {
        try await IBUClient.sample(now: now).homeFeed(now: now)
    }

    @Test func nextRaceNamesItsPlaceAndStart() async throws {
        let start = try Date("2026-12-05T14:00:00Z", strategy: .iso8601)
            .formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        let race = String(localized: RaceKind.womenPursuit.title)

        #expect(
            String(localized: SiriAnswer.nextRace(in: try await Self.feed()))
                == "Next race: \(race), Nordvik, \(start).")
    }

    @Test func nothingScheduled() {
        #expect(String(localized: SiriAnswer.nextRace(in: HomeFeed(events: [], races: []))) == "No race scheduled.")
    }

    /// Names as a voice reads them, not in capitals.
    @Test func latestResultReadsItsPodium() async throws {
        let race = String(localized: RaceKind.menPursuit.title)

        #expect(
            String(localized: SiriAnswer.latestResult(in: try await Self.feed()))
                == "\(race), Nordvik: Aksel Vangen wins, ahead of Hugo Martel and Lukas Brandt.")
    }

    @Test func noResultsYet() {
        #expect(String(localized: SiriAnswer.latestResult(in: HomeFeed(events: [], races: []))) == "No results yet.")
    }
}
