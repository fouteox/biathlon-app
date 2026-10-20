import BiathlonKit
import SwiftUI

/// How a race's phase reads, in the app and in its Live Activity.
extension Competition.State {
    var label: LocalizedStringResource {
        switch self {
        case .scheduled: "Upcoming"
        case .live: "Live"
        case .cancelled: "Cancelled"
        case .finished: "Finished"
        }
    }

    var tint: Color {
        switch self {
        case .live: .red
        case .cancelled: .gray
        case .finished: .secondary
        case .scheduled: .blue
        }
    }

    /// The state in race lists, where upcoming goes without a badge: the start time says it.
    var badge: Text? {
        guard self != .scheduled else { return nil }
        return Text(label).foregroundStyle(tint)
    }
}
