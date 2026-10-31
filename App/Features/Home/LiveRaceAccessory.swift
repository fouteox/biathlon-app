import BiathlonKit
import SwiftUI

/// The race being run, above the tab bar on every tab: its name, who leads, and the race itself
/// on a tap. In line with a collapsed tab bar, the name alone.
struct LiveRaceAccessory: View {
    let race: Competition
    let results: RaceResults?
    let action: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Competition.State.live.tint)
                    .labelStyle(placement == .inline ? .iconOnly : .titleAndIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.title)
                        .font(.headline)
                        .lineLimit(1)
                    if placement != .inline, let leader = results?.standings.first {
                        Text("Leader \(leader.shortName ?? leader.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live-accessory")
    }
}
