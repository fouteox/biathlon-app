import BiathlonKit
import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case event(BiathlonEvent)
    case race(Competition)
    case athlete(id: String, name: String)
}

extension View {
    func navigationDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .event(let event): EventView(event: event)
            case .race(let race): RaceView(race: race)
            case .athlete(let id, let name): AthleteView(athleteID: id, name: name)
            }
        }
    }

    /// Source credit, as offered in the email to the IBU. A bar with no
    /// background: content scrolls beneath it with the system scroll edge
    /// effect (Liquid Glass).
    func ibuAttribution() -> some View {
        safeAreaBar(edge: .bottom) {
            Text("Data: IBU Datacenter · biathlonresults.com")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }
}

struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Unable to load", systemImage: "wifi.exclamationmark")
            } description: {
                Self.message(for: error)
            } actions: {
                Button("Try again") { Task { await retry() } }
            }
        case .loaded(let value):
            content(value)
        }
    }

    /// Network errors already carry a plain system message ("The Internet
    /// connection appears to be offline."); the details of any other error
    /// go to the log, not to the screen.
    private static func message(for error: any Error) -> Text {
        if let error = error as? URLError {
            Text(error.localizedDescription)
        } else {
            Text("Results are temporarily unavailable.")
        }
    }
}

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
}

struct RaceRow: View {
    let race: Competition

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(race.shortDescription).font(.headline)
                Text(race.startTime, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(race.state.label)
                .font(.caption.bold())
                .foregroundStyle(race.state.tint)
        }
    }
}
