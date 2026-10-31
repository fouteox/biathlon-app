import BiathlonKit
import SwiftUI

/// A nation's athletes, from the World Cup overall standings: the API lists them nowhere else.
struct NationView: View {
    let nation: String
    @State private var category: RaceCategory

    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<SeasonStandings>()

    init(nation: String, category: RaceCategory) {
        self.nation = nation
        _category = State(initialValue: category)
    }

    var body: some View {
        LoadableView(state: loader.state, retry: load) { loaded in
            let athletes = loaded.standings.athletes(of: nation)
            List {
                Section {
                    if athletes.isEmpty {
                        ContentUnavailableView("No athletes in the standings", systemImage: "person.3")
                    } else {
                        ForEach(athletes) { StandingRow(row: $0, category: category) }
                    }
                } header: {
                    Text("\(category.title) · \(Text(StandingsDiscipline.total.label))")
                } footer: {
                    Text("The athletes who scored World Cup points in \(loaded.season.displayName).")
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle(Nation.namedTitle(nation))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Picker("Category", selection: $category) {
                    ForEach(RaceCategory.withStandings) { Text($0.title).tag($0) }
                }
            }
            // A text item and a symbol item in groups of their own.
            ToolbarSpacer(.fixed)
            ToolbarItem {
                FavoriteButton(kind: .nation, key: nation, name: Nation.localizedName(nation), nation: nation)
            }
        }
        // As on the standings, only a new category shows the loading state.
        .onChange(of: category) { loader.reset() }
        .task(id: category) { await load() }
    }

    private func load() async {
        await loader.load { try await ibu.worldCupStandings(category: category, discipline: .total, now: .now) }
    }
}
