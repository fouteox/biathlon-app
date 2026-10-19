import BiathlonKit
import SwiftUI

struct CalendarView: View {
    @Environment(\.ibu) private var ibu
    @State private var season = SeasonID.current
    @State private var state: Loadable<[BiathlonEvent]> = .loading

    /// Saison en cours et les quatre précédentes.
    private var seasons: [SeasonID] {
        sequence(first: SeasonID.current) { $0.previous }.prefix(5).map(\.self)
    }

    var body: some View {
        LoadableView(state: state, retry: load) { events in
            List(events) { event in
                NavigationLink(value: Route.event(event)) {
                    HStack {
                        Text(Nation.flag(event.nation)).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.shortDescription).font(.headline)
                            Text(event.startDate.formatted(.dateTime.day().month()) + " – " + event.endDate.formatted(.dateTime.day().month()))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if event.isWorldChampionships {
                            Text("Mondiaux").font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("Calendrier non publié", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
        .navigationTitle("Calendrier")
        .toolbar {
            Picker("Saison", selection: $season) {
                ForEach(seasons, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        .ibuAttribution()
        .task(id: season) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await ibu.events(season: season).sorted { $0.startDate < $1.startDate })
        } catch {
            state = .failed(error)
        }
    }
}

struct EventView: View {
    let event: BiathlonEvent
    @Environment(\.ibu) private var ibu
    @State private var state: Loadable<[Competition]> = .loading

    var body: some View {
        LoadableView(state: state, retry: load) { races in
            List(races) { race in
                NavigationLink(value: Route.race(race)) { RaceRow(race: race) }
            }
        }
        .navigationTitle("\(Nation.flag(event.nation)) \(event.shortDescription)")
        .ibuAttribution()
        .task { await load() }
    }

    private func load() async {
        do {
            state = .loaded(try await ibu.competitions(eventID: event.id).sorted { $0.startTime < $1.startTime })
        } catch {
            state = .failed(error)
        }
    }
}
