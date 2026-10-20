import BiathlonKit
import SwiftUI

/// How a race's state reads in race lists.
extension Competition.State {
    /// Upcoming is the usual state and goes without a badge: the start time says it.
    var badge: Text? {
        switch self {
        case .scheduled: nil
        case .live: Text("Live").foregroundStyle(.red)
        case .cancelled: Text("Cancelled").foregroundStyle(.gray)
        case .finished: Text("Finished").foregroundStyle(.secondary)
        }
    }
}
