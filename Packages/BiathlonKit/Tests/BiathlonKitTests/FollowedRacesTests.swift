import Foundation
import Testing

@testable import BiathlonKit

struct FollowedRacesTests {
    @Test func keepsAFollowedRaceUntilTwoDaysAfterItsStart() {
        var followed = FollowedRaces()
        followed.follow("R2", startingAt: date("2026-11-29T12:00:00Z"))
        followed.follow("R1", startingAt: date("2026-11-26T15:15:00Z"))
        #expect(followed.raceIDs == ["R1", "R2"])
        #expect(followed.pruned(at: date("2026-11-28T15:14:00Z")).raceIDs == ["R1", "R2"])
        #expect(followed.pruned(at: date("2026-11-28T15:15:00Z")).raceIDs == ["R2"])
    }

    @Test func forgetsARaceOnceUnfollowed() {
        var followed = FollowedRaces()
        followed.follow("R1", startingAt: date("2026-11-26T15:15:00Z"))
        #expect(followed.contains("R1"))
        followed.unfollow("R1")
        #expect(!followed.contains("R1"))
        #expect(followed.isEmpty)
    }

    @Test func roundTripsThroughCoding() throws {
        var followed = FollowedRaces()
        followed.follow("R1", startingAt: date("2026-11-26T15:15:00Z"))
        let data = try JSONEncoder().encode(followed)
        #expect(try JSONDecoder().decode(FollowedRaces.self, from: data) == followed)
    }
}
