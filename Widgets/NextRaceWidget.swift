import BiathlonKit
import SwiftUI
import WidgetKit

/// The live race, otherwise the next one, on the Home Screen and the Lock Screen.
struct NextRaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextRace", provider: NextRaceProvider()) { entry in
            NextRaceView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next race")
        .description("The live race, otherwise the next one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

/// What the widget shows at `date`.
nonisolated struct NextRaceEntry: TimelineEntry {
    struct Race: Sendable {
        let id: String
        let ibuName: String
        let place: String?
        let nation: String?
        let start: Date
        let isLive: Bool
    }

    let date: Date
    /// `nil` when no race is ahead, or when the calendar couldn't load.
    let race: Race?
    let isUnavailable: Bool

    init(date: Date, race: Race?, isUnavailable: Bool = false) {
        self.date = date
        self.race = race
        self.isUnavailable = isUnavailable
    }

    init(date: Date, feed: HomeFeed) {
        let race = feed.upcomingRace
        let event = race.flatMap(feed.event(of:))
        self.init(
            date: date,
            race: race.map {
                Race(
                    id: $0.id, ibuName: $0.shortDescription, place: event?.shortDescription,
                    nation: event?.nation, start: $0.startTime, isLive: $0.state == .live)
            })
    }

    /// A fictional race, for the widget gallery and the placeholder WidgetKit greys out.
    static func sample(now: Date, isLive: Bool = false) -> Self {
        Self(
            date: now,
            race: Race(
                id: "BT2627SWRLCP01SMSP", ibuName: "Men 10 km Sprint", place: "Kontiolahti", nation: "FIN",
                start: isLive ? now : now.addingTimeInterval(2 * 86_400), isLive: isLive))
    }
}

/// Reads the calendar through the server's cache, as the app does.
nonisolated struct NextRaceProvider: TimelineProvider {
    /// After a failed load, as often as while a race is live.
    private static let retryInterval = HomeFeed.widgetLiveInterval

    private let ibu = IBUClient(cachedBy: Bundle.main.serverURL.map { ServerClient(baseURL: $0) })

    func placeholder(in context: Context) -> NextRaceEntry { .sample(now: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextRaceEntry) -> Void) {
        guard !context.isPreview else { return completion(.sample(now: .now)) }
        Task { completion(await load(now: .now).entry) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextRaceEntry>) -> Void) {
        Task {
            let (entry, reload) = await load(now: .now)
            completion(Timeline(entries: [entry], policy: .after(reload)))
        }
    }

    /// The entry for `now`, and when to load the next one.
    private func load(now: Date) async -> (entry: NextRaceEntry, reload: Date) {
        do {
            let feed = try await ibu.featuredRaces(now: now)
            return (NextRaceEntry(date: now, feed: feed), feed.widgetReloadDate(now: now))
        } catch {
            return (NextRaceEntry(date: now, race: nil, isUnavailable: true), now + Self.retryInterval)
        }
    }
}

struct NextRaceView: View {
    let entry: NextRaceEntry
    @Environment(\.widgetFamily) private var family

    private static let startFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month().hour().minute()

    var body: some View {
        // A tap opens the race itself (HIG Widgets: deep link to what the widget shows).
        content.widgetURL(entry.race.map { DeepLink.race(id: $0.id, name: $0.ibuName).url })
    }

    @ViewBuilder private var content: some View {
        if let race = entry.race {
            let title = RaceKind.title(ofRace: race.id, ibuName: race.ibuName)
            switch family {
            case .accessoryInline:
                Text("\(title) · \(when(race))")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(title).font(.headline).widgetAccentable()
                    when(race)
                    if let place = race.place { Text(place) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    (race.isLive ? Text(Competition.State.live.label) : Text("Next race"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(race.isLive ? Competition.State.live.tint : .secondary)
                    Text(title).font(.headline).lineLimit(2)
                    if let place = race.place {
                        Text(Nation.titled(place, nation: race.nation)).font(.subheadline).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(race.start, format: Self.startFormat).font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            (entry.isUnavailable ? Text("Unable to load") : Text("No races"))
                .font(family == .accessoryInline ? nil : .headline)
                .foregroundStyle(.secondary)
        }
    }

    /// Live, or the start's day and time.
    private func when(_ race: NextRaceEntry.Race) -> Text {
        race.isLive ? Text(Competition.State.live.label) : Text(race.start, format: Self.startFormat)
    }
}

#Preview("Next race", as: .systemSmall) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.sample(now: .now)
    NextRaceEntry.sample(now: .now, isLive: true)
    NextRaceEntry(date: .now, race: nil)
    NextRaceEntry(date: .now, race: nil, isUnavailable: true)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    NextRaceWidget()
} timeline: {
    NextRaceEntry.sample(now: .now)
    NextRaceEntry.sample(now: .now, isLive: true)
}
