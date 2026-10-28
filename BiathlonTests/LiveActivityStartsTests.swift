import BiathlonKit
import Foundation
import Testing

@testable import Biathlon

struct LiveActivityStartsTests {
    /// ActivityKit gives no token while Live Activities are off: the deletion names the last one sent.
    @Test func deletesTheFavoritesWithTheLastTokenSent() async throws {
        let defaults = try UserDefaults.empty()
        let server = ServerStub([
            "PUT /v1/live-activity-starts/aa": [.init(204)],
            "PUT /v1/live-activity-starts/bb": [.init(204)],
            "DELETE /v1/live-activity-starts/bb": [.init(204)],
        ])
        let starts = LiveActivityStarts(
            appAttest: AppAttest(server: server.client, service: FakeAttestService(), defaults: defaults),
            defaults: defaults)
        let favorites = FavoriteSet(athleteIDs: ["A1"], nations: ["FRA"])

        await starts.sync(.init(token: "aa", isEnabled: true, favorites: favorites, races: []))
        await starts.sync(.init(token: "bb", isEnabled: true, favorites: favorites, races: []))
        await starts.sync(.init(token: nil, isEnabled: false, favorites: favorites, races: []))
        // Nothing is left on the server to delete.
        await starts.sync(.init(token: nil, isEnabled: false, favorites: favorites, races: []))

        #expect(
            await server.routes.filter { $0.contains("/live-activity-starts/") } == [
                "PUT /v1/live-activity-starts/aa",
                "PUT /v1/live-activity-starts/bb",
                "DELETE /v1/live-activity-starts/bb",
            ])
    }

    /// The app syncs again when it comes back: a registration the server didn't take is sent
    /// again, one it took is not.
    @Test func sendsARegistrationAgainOnlyUntilTheServerTakesIt() async throws {
        let defaults = try UserDefaults.empty()
        let server = ServerStub(["PUT /v1/live-activity-starts/aa": [.init(503), .init(204)]])
        let starts = LiveActivityStarts(
            appAttest: AppAttest(server: server.client, service: FakeAttestService(), defaults: defaults),
            defaults: defaults)
        let registration = LiveActivityStarts.Registration(
            token: "aa", isEnabled: false, favorites: FavoriteSet(athleteIDs: [], nations: []), races: ["R1"])

        await starts.sync(registration)
        await starts.sync(registration)
        await starts.sync(registration)

        #expect(await server.requests(to: "PUT /v1/live-activity-starts/aa").count == 2)
    }

    /// A followed race reaches the server whether or not starting for favorites is on.
    @Test func sendsTheFollowedRacesAndTheFavoritesOnlyWhileStartingForThemIsOn() async throws {
        let favorites = FavoriteSet(athleteIDs: ["A1"], nations: ["FRA"])
        let off = LiveActivityStarts.Registration(token: "aa", isEnabled: false, favorites: favorites, races: ["R1"])
        let body = try #require(off.body(environment: .sandbox))
        #expect(
            try Self.json(body)
                == Self.json(.init(environment: .sandbox, favorites: .init(athleteIDs: [], nations: []), races: ["R1"]))
        )
        let on = LiveActivityStarts.Registration(token: "aa", isEnabled: true, favorites: favorites, races: ["R1"])
        #expect(
            try Self.json(#require(on.body(environment: .sandbox)))
                == Self.json(.init(environment: .sandbox, favorites: favorites, races: ["R1"])))
        // Nothing left to follow: the server's copy is deleted.
        #expect(
            LiveActivityStarts.Registration(token: "aa", isEnabled: false, favorites: favorites, races: []).body(
                environment: .sandbox) == nil)
        #expect(
            LiveActivityStarts.Registration(
                token: "aa", isEnabled: true, favorites: .init(athleteIDs: [], nations: []), races: []
            ).body(environment: .sandbox) == nil)
    }

    @Test func keepsTheFollowedRacesAcrossLaunchesUntilUnfollowed() throws {
        let defaults = try UserDefaults.empty()
        let none = FavoriteSet(athleteIDs: [], nations: [])
        LiveActivityStarts(appAttest: nil, defaults: defaults).follow("R1", startingAt: .now + 3600)

        let relaunched = LiveActivityStarts(appAttest: nil, defaults: defaults)
        #expect(relaunched.registration(favorites: none).races == ["R1"])
        relaunched.unfollow("R1")
        #expect(LiveActivityStarts(appAttest: nil, defaults: defaults).registration(favorites: none).races == [])
    }

    private static func json(_ registration: LiveActivityStartsRegistration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(registration)
    }
}
