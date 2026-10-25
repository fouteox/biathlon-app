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

        await starts.sync(.init(token: "aa", isEnabled: true, favorites: favorites))
        await starts.sync(.init(token: "bb", isEnabled: true, favorites: favorites))
        await starts.sync(.init(token: nil, isEnabled: false, favorites: favorites))
        // Nothing is left on the server to delete.
        await starts.sync(.init(token: nil, isEnabled: false, favorites: favorites))

        #expect(
            await server.routes.filter { $0.contains("/live-activity-starts/") } == [
                "PUT /v1/live-activity-starts/aa",
                "PUT /v1/live-activity-starts/bb",
                "DELETE /v1/live-activity-starts/bb",
            ])
    }
}
