import BiathlonKit
import SwiftUI

struct CalendarView: View {
    @Environment(\.ibu) private var ibu
    @Environment(\.calendar) private var calendar
    @State private var season = SeasonID.containing(.now)
    @State private var loader = Loader<[BiathlonEvent]>()
    /// The season whose list was scrolled to the event to show, so that coming back from an
    /// event leaves the list where it was.
    @State private var scrolledSeason: SeasonID?

    /// Every season with races, back to the oldest.
    private let seasons = SeasonID.since(.firstWithRaces, now: .now)

    var body: some View {
        LoadableView(state: loader.state, retry: load) { events in
            ScrollViewReader { proxy in
                List {
                    // By month: the season runs from November to March, and a month is how
                    // people place an event in time.
                    ForEach(events.groupedByMonth(calendar: calendar)) { month in
                        Section {
                            ForEach(month.items) { event in
                                NavigationLink(value: Route.event(event)) {
                                    EventRow(event: event, phase: event.phase(at: .now, calendar: calendar))
                                }
                            }
                        } header: {
                            Text(month.start, format: .dateTime.month(.wide).year())
                        }
                    }
                }
                .refreshable { await load() }
                .overlay {
                    if events.isEmpty {
                        ContentUnavailableView("Calendar not published", systemImage: "calendar.badge.exclamationmark")
                    }
                }
                // The season opens on the event underway, or the next one, not on November: once
                // per season, as the list appears again on the way back from an event.
                .onAppear {
                    guard scrolledSeason != season else { return }
                    scrolledSeason = season
                    if let event = events.eventToShow(at: .now, calendar: calendar) {
                        proxy.scrollTo(event.id, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            SeasonPicker(seasons: seasons, selection: $season)
        }
        // The task also runs again each time the screen reappears (back from an
        // event): it refreshes the list in place, so the scroll position stays.
        // Only a new season shows the loading state.
        .onChange(of: season) { loader.reset() }
        .task(id: season) { await load() }
    }

    private func load() async {
        await loader.load { try await ibu.events(season: season) }
    }
}

struct EventView: View {
    let event: BiathlonEvent
    @Environment(\.ibu) private var ibu
    @Environment(\.calendar) private var calendar
    @State private var loader = Loader<[Competition]>()

    var body: some View {
        LoadableView(state: loader.state, retry: load) { races in
            List {
                // By day: the day once in the header, the time on each row.
                ForEach(races.groupedByDay(calendar: calendar)) { day in
                    Section {
                        ForEach(day.items) { race in
                            NavigationLink(value: Route.race(race)) { RaceRow(race: race, start: .timeOnly) }
                        }
                    } header: {
                        Text(day.start, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    }
                }
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
        await loader.load { try await ibu.competitions(eventID: event.id) }
    }
}

/// An event's place, dates and championship, in the calendar and at the top of the home screen.
struct EventRow: View {
    let event: BiathlonEvent
    /// Where the event stands, when the list spans a whole season: past events recede, the one
    /// underway says so.
    var phase: BiathlonEvent.Phase?

    var body: some View {
        RowStack { _ in
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if phase == .underway {
                Text("Underway").font(.caption.bold()).foregroundStyle(Competition.State.live.tint)
            }
        }
        .foregroundStyle(phase == .past ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }
}

extension BiathlonEvent {
    /// First to last day of the event.
    fileprivate var dates: Range<Date> {
        startDate..<max(startDate, endDate)
    }
}
