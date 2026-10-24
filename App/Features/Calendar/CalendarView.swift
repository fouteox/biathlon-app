import BiathlonKit
import SwiftUI

struct CalendarView: View {
    @Environment(\.ibu) private var ibu
    @State private var season = SeasonID.containing(.now)
    @State private var loader = Loader<[BiathlonEvent]>()

    /// Current season and the four before it.
    private let seasons = SeasonID.recent(5, now: .now)

    var body: some View {
        LoadableView(state: loader.state, retry: load) { events in
            List(events) { event in
                NavigationLink(value: Route.event(event)) {
                    HStack {
                        NationMark(code: event.nation).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.shortDescription).font(.headline)
                            Text(event.dates, format: .interval.day().month())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if event.isWorldChampionships {
                                Text("World Championships").font(.caption.bold()).foregroundStyle(.tint)
                            }
                            if event.isOlympics {
                                Text("Olympic Games").font(.caption.bold()).foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("Calendar not published", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            Picker("Season", selection: $season) {
                ForEach(seasons, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        // The task also runs again each time the screen reappears (back from an
        // event): it refreshes the list in place, so the scroll position stays.
        // Only a new season shows the loading state.
        .onChange(of: season) { loader.reset() }
        .task(id: season) { await load() }
    }

    private func load() async {
        await loader.load { try await ibu.events(season: season).sorted { $0.startDate < $1.startDate } }
    }
}

struct EventView: View {
    let event: BiathlonEvent
    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<[Competition]>()

    var body: some View {
        LoadableView(state: loader.state, retry: load) { races in
            List(races) { race in
                NavigationLink(value: Route.race(race)) { RaceRow(race: race) }
            }
            .refreshable { await load() }
            .overlay {
                if races.isEmpty {
                    ContentUnavailableView("Schedule not published", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
        .navigationTitle(Nation.titled(event.shortDescription, nation: event.nation))
        .task { await load() }
    }

    private func load() async {
        await loader.load { try await ibu.competitions(eventID: event.id).sorted { $0.startTime < $1.startTime } }
    }
}

extension BiathlonEvent {
    /// First to last day of the event.
    fileprivate var dates: Range<Date> {
        startDate..<max(startDate, endDate)
    }
}
