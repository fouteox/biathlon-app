import BiathlonKit
import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case event(BiathlonEvent)
    case race(Competition)
    /// A race known by its ID alone, such as an athlete's result, with its title.
    case raceID(String, title: String)
    case athlete(id: String, name: String)
    /// A nation's athletes in the standings of `category`.
    case nation(code: String, category: RaceCategory)
}

extension View {
    func navigationDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .event(let event): EventView(event: event)
            case .race(let race): RaceView(race: race)
            case .raceID(let id, let title): RaceByIDView(raceID: id, title: title)
            case .athlete(let id, let name): AthleteView(athleteID: id, name: name)
            case .nation(let code, let category): NationView(nation: code, category: category)
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
            LoadingPlaceholder()
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

/// How a list row lays out its columns. At the accessibility text sizes they
/// stack, text above the secondary columns, so the text keeps the row's whole
/// width (HIG Typography and Layout).
enum RowColumns: Equatable {
    case sideBySide
    case stacked

    init(_ size: DynamicTypeSize) {
        self = size.isAccessibilitySize ? .stacked : .sideBySide
    }

    func layout(spacing: CGFloat?) -> AnyLayout {
        switch self {
        case .sideBySide: AnyLayout(HStackLayout(spacing: spacing))
        case .stacked: AnyLayout(VStackLayout(alignment: .leading))
        }
    }

    /// The alignment of a trailing column's lines: on the row's trailing edge
    /// side by side, on the text above once stacked.
    var trailingAlignment: HorizontalAlignment {
        switch self {
        case .sideBySide: .trailing
        case .stacked: .leading
        }
    }
}

/// A row's columns, laid out for the current text size. The main text column
/// takes the free width (`.frame(maxWidth: .infinity, alignment: .leading)`)
/// rather than a `Spacer`, which would add height once the columns stack.
struct RowStack<Content: View>: View {
    /// The space between columns side by side.
    var spacing: CGFloat?
    @ViewBuilder let content: (RowColumns) -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = RowColumns(dynamicTypeSize)
        let layout = columns.layout(spacing: spacing)
        layout { content(columns) }
    }
}

/// What a first load shows: placeholder rows in the shape of the lists every screen holds,
/// rather than a spinner on an empty screen. VoiceOver reads it as the spinner it replaces.
private struct LoadingPlaceholder: View {
    private struct Row: Hashable {
        let title: String
        let detail: String
    }

    /// Varied lengths, so the rows look like content; redacted, they never show.
    private static let rows = [
        Row(title: "Sprint 10 km", detail: "Saturday, 29 November, 14:15"),
        Row(title: "Pursuit 12.5 km", detail: "Sunday, 30 November, 12:30"),
        Row(title: "Individual 20 km", detail: "Wednesday, 3 December, 11:45"),
        Row(title: "Relay 4 × 7.5 km", detail: "Saturday, 6 December, 14:30"),
        Row(title: "Mass start 15 km", detail: "Sunday, 7 December, 15:00"),
        Row(title: "Single mixed relay", detail: "Thursday, 11 December, 13:00"),
    ]

    var body: some View {
        List(Self.rows, id: \.self) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.headline)
                Text(verbatim: row.detail).font(.subheadline)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityRepresentation { ProgressView() }
    }
}

struct RaceRow: View {
    let race: Competition

    var body: some View {
        RowStack { _ in
            VStack(alignment: .leading, spacing: 2) {
                Text(race.title).font(.headline)
                RaceStart(race: race)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
