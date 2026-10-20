import ActivityKit
import BiathlonKit
import Foundation

/// A race's Live Activity, on the Lock Screen and in the Dynamic Island.
///
/// The server updates it on the race's broadcast channel (server/src/live.ts) with a
/// `content-state` that decodes into `RaceLiveState`. Nonisolated: ActivityKit
/// encodes and decodes it outside the main actor.
nonisolated struct RaceActivityAttributes: ActivityAttributes {
    typealias ContentState = RaceLiveState

    let raceID: String
    let name: String
    /// The broadcast channel it subscribes to: the server replaces a channel APNs no
    /// longer knows, and the app then moves the activity to the new one.
    let channelID: String
    /// When ActivityKit shows a scheduled activity (`RaceLiveState.activityStart`), which
    /// it can't move: the app schedules it again when the race moves. `nil` once started.
    let scheduledStart: Date?
}

#if DEBUG
    extension RaceActivityAttributes {
        /// The race `RaceLiveState.demo` plays, in Xcode previews and the app's developer settings.
        static let demoRaceID = "demo"
        static let demoName = "Men's 10km Sprint"
    }
#endif
