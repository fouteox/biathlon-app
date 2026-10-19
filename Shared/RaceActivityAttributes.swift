import ActivityKit
import BiathlonKit

/// A race's Live Activity, on the Lock Screen and in the Dynamic Island.
///
/// The server updates it on the race's broadcast channel (server/src/live.ts) with a
/// `content-state` that decodes into `RaceLiveState`. Nonisolated: ActivityKit
/// encodes and decodes it outside the main actor.
nonisolated struct RaceActivityAttributes: ActivityAttributes {
    typealias ContentState = RaceLiveState

    let raceID: String
    let name: String
}
