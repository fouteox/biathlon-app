import BiathlonKit
import SwiftData
import SwiftUI

struct RaceView: View {
    let race: Competition
    @Environment(\.ibu) private var ibu
    @State private var state: Loadable<RaceResults> = .loading
    @Query private var favorites: [Favorite]

    private var isLive: Bool {
        (state.value?.competition ?? race).state == .live
    }

    var body: some View {
        LoadableView(state: state, retry: load) { results in
            List {
                Section {
                    RaceRow(race: results.competition ?? race)
                    if results.isStartList && !results.isResult {
                        Text("Liste de départ").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(results.standings) { row in
                        if results.competition?.isRelay ?? race.isRelay {
                            DisclosureGroup {
                                ForEach(results.legs(of: row)) { leg in athleteLink(leg) }
                            } label: {
                                ResultLine(row: row, highlighted: isFavorite(row))
                            }
                        } else {
                            athleteLink(row)
                        }
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if results.rows.isEmpty {
                    ContentUnavailableView("Pas encore de liste de départ", systemImage: "clock")
                }
            }
        }
        .navigationTitle(race.shortDescription)
        .navigationBarTitleDisplayMode(.inline)
        .ibuAttribution()
        .task { await load() }
        .task(id: isLive) {
            guard isLive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: HomeModel.livePollInterval)
                await load()
            }
        }
    }

    @ViewBuilder
    private func athleteLink(_ row: ResultRow) -> some View {
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) {
                ResultLine(row: row, highlighted: isFavorite(row))
            }
        } else {
            ResultLine(row: row, highlighted: isFavorite(row))
        }
    }

    private func isFavorite(_ row: ResultRow) -> Bool {
        favorites.contains { $0.key == row.athleteID || ($0.kind == .nation && $0.key == row.nation) }
    }

    private func load() async {
        do {
            state = .loaded(try await ibu.results(raceID: race.id))
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }
}
