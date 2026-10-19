import BiathlonKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.ibu) private var ibu
    @State private var model = HomeModel()
    @Query private var favorites: [Favorite]
    @State private var showsNotificationSettings = false

    var body: some View {
        LoadableView(state: model.state, retry: reload) { snapshot in
            List {
                if let live = snapshot.live {
                    Section {
                        NavigationLink(value: Route.race(live)) {
                            LiveHeader(race: live)
                        }
                        if let results = snapshot.liveResults {
                            TopResults(rows: results.standings, limit: 5, favorites: favorites)
                        }
                    } header: {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.red)
                    }
                }

                if let next = snapshot.next {
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

                if let results = snapshot.latestResults, let race = snapshot.latestFinished {
                    let mine = favoriteRows(in: results)
                    if !mine.isEmpty {
                        Section("My favorites · \(race.shortDescription)") {
                            TopResults(rows: mine, limit: mine.count, favorites: favorites)
                        }
                    }
                    Section {
                        TopResults(rows: results.standings, limit: 3, favorites: favorites)
                        NavigationLink("All results", value: Route.race(race))
                    } header: {
                        Text("Latest result · \(race.shortDescription)")
                    }
                }

                if let event = snapshot.event {
                    Section {
                        NavigationLink(value: Route.event(event)) {
                            Label("\(Nation.flag(event.nation)) \(event.shortDescription)" as String, systemImage: "mappin.and.ellipse")
                        }
                    } header: {
                        Text("Event")
                    }
                }
            }
            .refreshable { await reload() }
        }
        .navigationTitle("Biathlon")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNotificationSettings = true
                } label: {
                    Label {
                        Text("Notifications", tableName: "Notifications")
                    } icon: {
                        Image(systemName: "bell")
                    }
                }
            }
        }
        .sheet(isPresented: $showsNotificationSettings) {
            NavigationStack { NotificationSettingsView() }
        }
        .ibuAttribution()
        .task { await reload() }
        // Auto-refresh while a race is live.
        .task(id: model.isLive) {
            guard model.isLive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: HomeModel.livePollInterval)
                await reload()
            }
        }
    }

    private func reload() async {
        await model.load(using: ibu)
    }

    private func favoriteRows(in results: RaceResults) -> [ResultRow] {
        let athletes = Set(favorites.filter { $0.kind == .athlete }.map(\.key))
        let nations = Set(favorites.filter { $0.kind == .nation }.map(\.key))
        return results.standings.filter { row in
            if let id = row.athleteID, athletes.contains(id) { return true }
            if let nat = row.nation, nations.contains(nat) { return true }
            return false
        }
    }
}

private struct LiveHeader: View {
    let race: Competition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(race.shortDescription).font(.title3.bold())
            Text("Start \(race.startTime, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct TopResults: View {
    let rows: [ResultRow]
    let limit: Int
    let favorites: [Favorite]

    var body: some View {
        ForEach(rows.prefix(limit)) { row in
            ResultLine(row: row, highlighted: isFavorite(row))
        }
    }

    private func isFavorite(_ row: ResultRow) -> Bool {
        favorites.contains { favorite in
            switch favorite.kind {
            case .athlete: favorite.key == row.athleteID
            case .nation: favorite.key == row.nation
            }
        }
    }
}

struct ResultLine: View {
    let row: ResultRow
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            Text(row.irm ?? row.rank ?? "–")
                .font(.headline.monospacedDigit())
                .frame(width: 36, alignment: .leading)
            Text(Nation.flag(row.nation))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.shortName ?? row.name)
                    .fontWeight(highlighted ? .bold : .regular)
                if let shootings = row.shootings {
                    Text(shootings)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.totalTime ?? "")
                    .font(.subheadline.monospacedDigit())
                if let behind = row.behind, behind != "0.0" {
                    Text(behind)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(highlighted ? Color.yellow.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
    }
}
