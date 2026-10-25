import BiathlonKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<HomeFeed>()
    @Query private var favorites: [Favorite]
    @Environment(SettingsPresentation.self) private var settingsPresentation

    var body: some View {
        LoadableView(state: loader.state, retry: load) { feed in
            List {
                if let live = feed.live {
                    Section {
                        NavigationLink(value: Route.race(live)) {
                            LiveHeader(race: live)
                        }
                        if let results = feed.liveResults {
                            TopResults(rows: results.standings.prefix(5), of: results, favorites: favoriteSet)
                        }
                    } header: {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.red)
                    }
                    if let results = feed.liveResults {
                        favoritesSection(results, of: live)
                    }
                }

                if let next = feed.next {
                    Section("Next race") {
                        NavigationLink(value: Route.race(next)) {
                            VStack(alignment: .leading, spacing: 4) {
                                RaceRow(race: next)
                                Text(next.startTime, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let results = feed.latestResults, let race = feed.latestFinished {
                    favoritesSection(results, of: race)
                    Section {
                        TopResults(rows: results.standings.prefix(3), of: results, favorites: favoriteSet)
                        NavigationLink("All results", value: Route.race(race))
                    } header: {
                        Text("Latest result · \(race.title)")
                    }
                }

                if let event = feed.event {
                    Section {
                        NavigationLink(value: Route.event(event)) {
                            Label(
                                Nation.titled(event.shortDescription, nation: event.nation),
                                systemImage: "mappin.and.ellipse")
                        }
                    } header: {
                        Text("Event")
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if feed.isEmpty {
                    ContentUnavailableView("No races", systemImage: "calendar")
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settingsPresentation.isPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task { await load() }
        .refreshingWhileLive(loader.state.value?.live != nil, action: load)
    }

    private func load() async {
        await loader.load { try await ibu.homeFeed(now: .now) }
    }

    private var favoriteSet: FavoriteSet { FavoriteSet(favorites) }

    /// Every favorite in the race, wherever they rank.
    @ViewBuilder
    private func favoritesSection(_ results: RaceResults, of race: Competition) -> some View {
        let favoriteRows = results.favoriteStandings(in: favoriteSet)
        if !favoriteRows.isEmpty {
            Section("Favorites · \(race.title)") {
                TopResults(rows: favoriteRows[...], of: results, favorites: favoriteSet)
            }
        }
    }
}

private struct LiveHeader: View {
    let race: Competition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(race.title).font(.title3.bold())
            Text("Start \(race.startTime, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct TopResults: View {
    let rows: ArraySlice<ResultRow>
    let results: RaceResults
    let favorites: FavoriteSet

    init(rows: ArraySlice<ResultRow>, of results: RaceResults, favorites: FavoriteSet) {
        self.rows = rows
        self.results = results
        self.favorites = favorites
    }

    var body: some View {
        ForEach(rows) { row in
            ResultLine(row: row, highlighted: results.isFavorite(row, in: favorites))
        }
    }
}

struct ResultLine: View {
    let row: ResultRow
    var highlighted = false
    @ScaledMetric(relativeTo: .headline) private var rankWidth = 36.0

    var body: some View {
        HStack(spacing: 12) {
            RankText(rank: row.irm ?? row.rank).frame(width: rankWidth, alignment: .leading)
            NationMark(code: row.nation)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.shortName ?? row.name)
                        .fontWeight(highlighted ? .bold : .regular)
                    if highlighted {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Favorite")
                    }
                }
                if let shootings = row.shootings {
                    Text(shootings)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let time = row.totalTime {
                    Text(time).font(.subheadline.monospacedDigit())
                }
                if let behind = row.behind, behind != "0.0" {
                    Text(behind)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rank or result status (DNF…), in the leading column of result rows.
struct RankText: View {
    let rank: String?

    var body: some View {
        if let rank {
            Text(rank).font(.headline.monospacedDigit())
        }
    }
}
