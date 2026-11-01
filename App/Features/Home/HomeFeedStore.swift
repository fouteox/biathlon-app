import BiathlonKit
import Observation

/// The home feed, kept by the app rather than by the Home screen: the live race it holds shows
/// at the bottom of every tab, and it keeps refreshing while a race is live, whichever tab is open.
@Observable
final class HomeFeedStore {
    private let client: IBUClient
    private let loader = Loader<HomeFeed>()

    init(client: IBUClient) {
        self.client = client
    }

    var state: Loadable<HomeFeed> { loader.state }

    /// The race being run, with its results as they stand.
    var live: (race: Competition, results: RaceResults?)? {
        guard let feed = state.value, let race = feed.live else { return nil }
        return (race, feed.liveResults)
    }

    /// The start the app waits for to fetch the feed again: the next race's, while none is live.
    var awaitedStart: Date? {
        live == nil ? state.value?.next?.startTime : nil
    }

    /// When to fetch the feed again for the awaited start, `nil` without one.
    func nextStartRefreshDate(now: Date) -> Date? {
        state.value?.nextStartRefreshDate(now: now)
    }

    func load() async {
        await loader.load { try await client.homeFeed(now: .now) }
    }
}
