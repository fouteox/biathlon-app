import BiathlonKit
import SwiftData
import SwiftUI

struct RaceView: View {
    let race: Competition
    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<RaceResults>()
    @Query private var favorites: [Favorite]

    private var isLive: Bool {
        (loader.state.value?.competition ?? race).state == .live
    }

    var body: some View {
        LoadableView(state: loader.state, retry: load) { results in
            List {
                Section {
                    RaceRow(race: results.competition ?? race)
                    if results.isStartList && !results.isResult {
                        Text("Start list").font(.caption).foregroundStyle(.secondary)
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
                    ContentUnavailableView("No start list yet", systemImage: "clock")
                }
            }
        }
        .navigationTitle(race.shortDescription)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshingWhileLive(isLive, action: load)
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
        FavoriteSet(favorites).contains(row)
    }

    private func load() async {
        await loader.load { try await ibu.results(raceID: race.id) }
    }
}
