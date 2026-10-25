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
