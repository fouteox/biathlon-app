import ActivityKit
import BiathlonKit
import SwiftUI
import WidgetKit

/// A race on the Lock Screen, in the Dynamic Island, and in the Smart Stack of a
/// paired Apple Watch or on CarPlay (the small family).
struct RaceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceActivityAttributes.self) { context in
            RaceActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseText(phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RaceProgress(state: context.state)
                }
            } compactLeading: {
                LiveSymbol(phase: context.state.phase)
            } compactTrailing: {
                LeaderMark(state: context.state)
            } minimal: {
                if let flag = Nation.flag(context.state.leaders.first?.nation) {
                    Text(flag)
                } else {
                    LiveSymbol(phase: context.state.phase)
                }
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct RaceActivityView: View {
    let context: ActivityViewContext<RaceActivityAttributes>
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.title).font(.headline).lineLimit(1)
                Spacer()
                PhaseText(phase: context.state.phase)
            }
            if activityFamily == .small {
                if let leader = context.state.leaders.first {
                    LeaderLine(leader: leader)
                } else if context.state.phase.canBeFollowedLive {
                    StartTime(date: context.state.startTime).font(.activityBody).foregroundStyle(.secondary)
                }
            } else {
                RaceProgress(state: context.state)
            }
        }
        .padding()
    }
}

/// The leaders, or the start time while nobody leads yet.
private struct RaceProgress: View {
    let state: RaceLiveState

    var body: some View {
        if !state.leaders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.leaders, id: \.self) { leader in LeaderLine(leader: leader) }
            }
        } else if state.phase.canBeFollowedLive {
            HStack {
                StartTime(date: state.startTime)
                Spacer()
                // Counts down to the start, then up from it.
                Text(state.startTime, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
            }
            .font(.activityBody)
            .foregroundStyle(.secondary)
        }
        // A cancelled race, or one over without results: the phase in the header says it all.
    }
}

private struct StartTime: View {
    let date: Date

    var body: some View {
        Text("Start \(date, format: .dateTime.hour().minute())")
    }
}

private struct LeaderLine: View {
    let leader: RaceLiveState.Leader

    var body: some View {
        HStack {
            Text(leader.rank).monospacedDigit().foregroundStyle(.secondary)
            Text(Nation.titled(leader.name, nation: leader.nation)).lineLimit(1)
            Spacer()
            if let result = leader.result {
                Text(result).monospacedDigit()
            }
        }
        .font(.activityBody)
    }
}

extension Font {
    /// The leaders and the start time: the HIG asks Live Activities for "large, heavier-weight
    /// text — a medium weight or higher", read at a glance.
    fileprivate static let activityBody = Font.subheadline.weight(.medium)
}

private struct PhaseText: View {
    let phase: Competition.State

    var body: some View {
        Text(phase.label).font(.caption.bold()).foregroundStyle(phase.tint)
    }
}

private struct LiveSymbol: View {
    let phase: Competition.State

    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(phase.tint)
    }
}

/// The leader's flag, the start time before anyone leads, or the phase of a race
/// that ended without results: narrow enough for the Dynamic Island's limited width
/// in landscape.
private struct LeaderMark: View {
    let state: RaceLiveState

    var body: some View {
        if let leader = state.leaders.first {
            Text(Nation.flag(leader.nation) ?? leader.rank)
        } else if state.phase.canBeFollowedLive {
            Text(state.startTime, format: .dateTime.hour().minute()).monospacedDigit()
        } else {
            LiveSymbol(phase: state.phase)
        }
    }
}

#if DEBUG
    private let previewAttributes = RaceActivityAttributes(
        raceID: RaceActivityAttributes.demoRaceID, name: RaceActivityAttributes.demoName,
        channelID: "preview")

    #Preview("Lock Screen", as: .content, using: previewAttributes) {
        RaceLiveActivity()
    } contentStates: {
        for state in RaceLiveState.demo(startTime: .now + 10 * 60) { state }
    }

    #Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
        RaceLiveActivity()
    } contentStates: {
        for state in RaceLiveState.demo(startTime: .now + 10 * 60) { state }
    }

    #Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
        RaceLiveActivity()
    } contentStates: {
        for state in RaceLiveState.demo(startTime: .now + 10 * 60) { state }
    }

    #Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
        RaceLiveActivity()
    } contentStates: {
        for state in RaceLiveState.demo(startTime: .now + 10 * 60) { state }
    }
#endif
