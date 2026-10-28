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
                // The event first: the races below are its own.
                if let event = feed.event {
                    Section("Event") {
                        NavigationLink(value: Route.event(event)) { EventRow(event: event) }
                    }
                }

                if let live = feed.live {
                    Section {
                        NavigationLink(value: Route.race(live)) {
                            LiveHeader(race: live)
                        }
                        if let results = feed.liveResults {
                            featured(results, top: 5)
                        }
                    } header: {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.red)
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
                    Section {
                        RaceRow(race: race)
                        featured(results, top: 3)
                        NavigationLink("All results", value: Route.race(race))
                    } header: {
                        latestResultHeader(race, in: feed)
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

    /// The top of the standings, then the favorites ranked below it.
    private func featured(_ results: RaceResults, top count: Int) -> some View {
        TopResults(
            rows: results.featuredStandings(top: count, favorites: favoriteSet), of: results, favorites: favoriteSet)
    }

    /// Names the race's event when it is not the one at the top, between two events.
    private func latestResultHeader(_ race: Competition, in feed: HomeFeed) -> Text {
        guard let event = feed.event(of: race), event != feed.event else {
            return Text("Latest result")
        }
        return Text("Latest result · \(Nation.titled(event.shortDescription, nation: event.nation))")
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
    let rows: [ResultRow]
    let results: RaceResults
    let favorites: FavoriteSet

    init(rows: [ResultRow], of results: RaceResults, favorites: FavoriteSet) {
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
        RowStack(spacing: 12) { columns in
            HStack(spacing: 12) {
                RankText(rank: row.irm ?? row.rank).frame(width: rankWidth, alignment: .leading)
                NationMark(code: row.nation)
            }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: columns.trailingAlignment, spacing: 2) {
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

#if DEBUG
    #Preview("Result lines, largest text size") {
        let rows = try? JSONDecoder().decode(
            [ResultRow].self,
            from: Data(
                #"""
                [{"IBUId":"BTFRA1","Name":"PERROT Eric","ShortName":"PERROT E.","Nat":"FRA","Rank":"1",
                  "Shootings":"0+0+1+0","TotalTime":"24:51.3","Behind":"0.0"},
                 {"IBUId":"BTNOR2","Name":"BOTN Johan-Olav Smoerdal","Nat":"NOR","Rank":"2",
                  "Shootings":"1+0+0+0","TotalTime":"25:03.7","Behind":"+12.4"}]
                """#.utf8))
        List {
            ForEach(rows ?? []) { ResultLine(row: $0, highlighted: $0.rank == "2") }
        }
        .environment(\.dynamicTypeSize, .accessibility5)
    }
#endif
