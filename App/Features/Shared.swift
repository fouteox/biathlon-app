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
}

extension LocalizedStringResource {
    /// Under the name of an athlete the IBU records as deceased, agreeing with their gender
    /// where the language needs it ("Décédée" in French).
    static func deceased(_ gender: Gender?) -> LocalizedStringResource {
        switch gender {
        case .woman:
            LocalizedStringResource(
                "deceased.woman", defaultValue: "Deceased",
                comment: "Under the name of a woman athlete the IBU records as deceased.")
        case .man, nil:
            LocalizedStringResource(
                "Deceased", comment: "Under the name of an athlete the IBU records as deceased.")
        }
    }
}

/// A nation's flag, or its IOC code when no flag is known.
struct NationMark: View {
    let code: String?

    var body: some View {
        if let flag = Nation.flag(code) {
            Text(flag)
        } else if let code {
            Text(code).font(.caption).foregroundStyle(.secondary)
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

struct RaceRow: View {
    let race: Competition

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(race.title).font(.headline)
                RaceStart(race: race)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            race.state.badge?.font(.caption.bold())
        }
    }
}

/// When a race starts, as every race screen writes it.
struct RaceStart: View {
    let race: Competition

    var body: some View {
        Text(race.startTime, format: .dateTime.weekday(.wide).day().month().hour().minute())
    }
}
