import BiathlonKit
import SwiftUI

struct StandingsView: View {
    /// Standings exist for men and women only.
    private static let categories: [RaceCategory] = [.men, .women]

    @Environment(\.ibu) private var ibu
    @State private var category = RaceCategory.men
    @State private var discipline = StandingsDiscipline.total
    @State private var loader = Loader<SeasonStandings>()

    var body: some View {
        LoadableView(state: loader.state, retry: load) { loaded in
            let standings = loaded.standings
            List {
                Section {
                    ForEach(standings.rows) { row in
                        StandingRow(row: row)
                    }
                } footer: {
                    if loaded.isFallback {
                        Text(
                            "Season \(loaded.season.displayName): the \(loaded.requestedSeason.displayName) standings will appear after the first race."
                        )
                    } else if let asOf = standings.asOf {
                        Text(asOf)
                    }
                }
            }
            .refreshable { await load() }
        }
        // Filters live in system bars rather than a custom header, so the
        // list scrolls under the glass with the scroll edge effect.
        .safeAreaBar(edge: .top) {
            Picker("Category", selection: $category) {
                ForEach(Self.categories) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .toolbar {
            Picker("Discipline", selection: $discipline) {
                ForEach(StandingsDiscipline.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .navigationTitle("Standings")
        .ibuAttribution()
        .task(id: [category.rawValue, discipline.rawValue]) {
            loader.reset()
            await load()
        }
    }

    private func load() async {
        await loader.load { try await ibu.worldCupStandings(category: category, discipline: discipline, now: .now) }
    }
}

extension StandingsDiscipline {
    var label: LocalizedStringResource {
        switch self {
        case .total: "Overall"
        case .sprint: "Sprint"
        case .pursuit: "Pursuit"
        case .individual: "Individual"
        case .massStart: "Mass start"
        case .nations: "Nations"
        }
    }
}

private struct StandingRow: View {
    let row: CupRow

    var body: some View {
        let content = HStack(spacing: 12) {
            Text(row.rank ?? "–")
                .font(.headline.monospacedDigit())
                .frame(width: 36, alignment: .leading)
            Text(Nation.flag(row.isNation ? row.nation ?? row.name : row.nation) ?? "")
            Text(row.shortName ?? row.name)
            if row.bibColors.contains("yellow") {
                Image(systemName: "tshirt.fill").foregroundStyle(.yellow)
            }
            Spacer()
            if let change = row.rankChange, change != 0 {
                Image(systemName: change < 0 ? "arrow.up" : "arrow.down")
                    .font(.caption)
                    .foregroundStyle(change < 0 ? .green : .red)
            }
            Text(row.score ?? "")
                .font(.subheadline.monospacedDigit().bold())
            if row.isNation, let nation = row.nation {
                FavoriteButton(kind: .nation, key: nation, name: row.name, nation: nation)
            }
        }
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) { content }
        } else {
            content
        }
    }
}
