import BiathlonKit
import Foundation
import Observation

/// Loads the home screen's `HomeFeed`.
@Observable
final class HomeModel {
    private(set) var state: Loadable<HomeFeed> = .loading

    /// Refresh interval while a race is live.
    static let livePollInterval: Duration = .seconds(20)

    func load(using client: IBUClient, now: Date = .now) async {
        do {
            state = .loaded(try await client.homeFeed(now: now))
        } catch is CancellationError {
            return
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    var isLive: Bool { state.value?.live != nil }
}
