import BiathlonKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(HomeFeedStore.self) private var homeFeed
    @Query private var favorites: [Favorite]
    @Environment(SettingsPresentation.self) private var settingsPresentation

    var body: some View {
        LoadableView(state: homeFeed.state, retry: homeFeed.load) { feed in
            List {
                // The anchor: the live race, otherwise the next one, under its event, the
                // context of the races below, rather than a section of its own.
                if let live = feed.live {
                    Section {
                        eventRow(feed.event)
                        NavigationLink(value: Route.race(live)) {
                            RaceHeading(race: live)
                        }
                        if let results = feed.liveResults {
                            featured(results, top: 5)
                        }
                    }
                } else if let next = feed.next {
                    Section {
                        eventRow(feed.event)
                        NavigationLink(value: Route.race(next)) {
                            RaceHeading(race: next)
                        }
                    }
                } else if let event = feed.event {
                    // No race ahead, as after a season's last race: the event on its own.
                    Section("Event") {
                        NavigationLink(value: Route.event(event)) { EventRow(event: event) }
                    }
                }

                // The next race keeps its section while another is live.
                if feed.live != nil, let next = feed.next {
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
                    // The race in the header and its start in the footer: the podium comes first.
                    Section {
                        featured(results, top: 3)
                        NavigationLink("All results", value: Route.race(race))
                    } header: {
                        Text("Latest result · \(race.title)")
                    } footer: {
                        latestResultFooter(race, in: feed)
                    }
                }
            }
            .refreshable { await homeFeed.load() }
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
    }

    private var favoriteSet: FavoriteSet { FavoriteSet(favorites) }

    /// The top of the standings, then the favorites ranked below it.
    private func featured(_ results: RaceResults, top count: Int) -> some View {
        TopResults(
            rows: results.featuredStandings(top: count, favorites: favoriteSet), of: results, favorites: favoriteSet)
    }

    /// The event over the races below it, which opens its schedule.
    @ViewBuilder
    private func eventRow(_ event: BiathlonEvent?) -> some View {
        if let event {
            NavigationLink(value: Route.event(event)) { EventRow(event: event) }
        }
    }

    /// When the race started and, between two events, where: its event is then not the one at the top.
    private func latestResultFooter(_ race: Competition, in feed: HomeFeed) -> Text {
        let start = Text(race.startTime, format: RaceStart.format)
        guard let event = feed.event(of: race), event != feed.event else { return start }
        return Text("\(start) · \(Text(Nation.titled(event.shortDescription, nation: event.nation)))")
    }
}

/// The race the home screen is anchored on, larger than the rows below it: its name, its start
/// and, while it is still to come, how far away that is.
private struct RaceHeading: View {
    let race: Competition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if race.state == .live {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Competition.State.live.tint)
            }
            Text(race.title).font(.title2.bold())
            if race.state == .live {
                Text("Start \(race.startTime, format: .dateTime.hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                RaceStart(race: race)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(race.startTime, style: .relative)
                    .font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
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
                RowName(name: row.shortName ?? row.name, highlighted: highlighted)
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
