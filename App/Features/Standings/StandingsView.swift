import BiathlonKit
import SwiftData
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
                } header: {
                    // Says which standings the filters menu shows, with the title left as on the other tabs.
                    Text("\(category.title) · \(Text(discipline.label))")
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
        .navigationTitle("Standings")
        // The filters sit in a toolbar menu rather than a bar pinned under the title: a large title
        // under that bar's scroll edge effect showed blurred and flickered (FB21613303).
        .toolbar {
            Menu("Filters", systemImage: "line.3.horizontal.decrease") {
                Picker("Category", selection: $category) {
                    ForEach(Self.categories) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Discipline", selection: $discipline) {
                    ForEach(StandingsDiscipline.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
        // The task also runs again each time the screen reappears (back from an
        // athlete): it refreshes the list in place, so the scroll position stays.
        // Only a new filter shows the loading state.
        .onChange(of: filters) { loader.reset() }
        .task(id: filters) { await load() }
    }

    /// The standings shown depend on both pickers.
    private var filters: [String] { [category.rawValue, discipline.rawValue] }

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
    @ScaledMetric(relativeTo: .headline) private var rankWidth = 36.0

    var body: some View {
        let content = HStack(spacing: 12) {
            // VoiceOver reads the standing in one go; the star stays a button of its own.
            RowStack(spacing: 12) { _ in
                HStack(spacing: 12) {
                    RankText(rank: row.rank).frame(width: rankWidth, alignment: .leading)
                    NationMark(code: row.isNation ? row.nation ?? row.name : row.nation)
                }
                HStack(spacing: 12) {
                    Text(row.isNation ? Nation.localizedName(row.nation ?? row.name) : row.shortName ?? row.name)
                    if row.bibColors.contains("yellow") {
                        // The leader's bib is yellow: here the color is the information.
                        Image(systemName: "tshirt.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Yellow bib")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    if let change = row.rankChange, change != 0 {
                        Image(systemName: change < 0 ? "arrow.up" : "arrow.down")
                            .font(.caption)
                            .foregroundStyle(change < 0 ? .green : .red)
                            .accessibilityLabel(change < 0 ? Text("Up") : Text("Down"))
                    }
                    if let score = row.score {
                        Text(score)
                            .font(.subheadline.monospacedDigit().bold())
                            .accessibilityLabel(Int(score).map { Text("\($0) points") } ?? Text(score))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if row.isNation, let nation = row.nation {
                FavoriteButton(kind: .nation, key: nation, name: Nation.localizedName(nation), nation: nation)
                    .labelStyle(.iconOnly)
            }
        }
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) { content }
        } else {
            content
        }
    }
}

#if DEBUG
    #Preview("Standing rows, largest text size") {
        let rows = try? JSONDecoder().decode(
            [CupRow].self,
            from: Data(
                #"""
                [{"Rank":"1","Bibs":[{"Color":"yellow"}],"IBUId":"BTFRA1","Name":"PERROT Eric",
                  "ShortName":"PERROT E.","Nat":"FRA","Score":"1263"},
                 {"Rank":"3","IBUId":"BTNOR2","Name":"BOTN Johan-Olav Smoerdal","Nat":"NOR","Score":968,"RnkDiff":-1},
                 {"Rank":"1","Name":"France","Nat":"FRA","Score":"2900"}]
                """#.utf8))
        NavigationStack {
            List {
                ForEach(rows ?? []) { StandingRow(row: $0) }
            }
        }
        .environment(\.dynamicTypeSize, .accessibility5)
        .modelContainer(for: Favorite.self, inMemory: true)
    }
#endif
