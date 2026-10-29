import BiathlonKit
import SwiftUI

/// A nation's athletes, from the World Cup overall standings: the API lists them nowhere else.
struct NationView: View {
    let nation: String
    @State private var category: RaceCategory

    @Environment(\.ibu) private var ibu
    @Environment(\.news) private var news
    @State private var loader = Loader<SeasonStandings>()
    /// Loaded on its own: without them, the screen has no news section.
    @State private var headlines = Loader<[Headline]>()

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
                if let headlines = headlines.state.value {
                    let familyNames = athletes.compactMap(\.familyName)
                    HeadlinesSection(
                        headlines: headlines.filter { headline in
                            familyNames.contains { headline.mentions(familyName: $0) }
                        })
                }
            }
            .refreshable {
                async let standings: Void = load()
                async let news: Void = loadHeadlines()
                _ = await (standings, news)
            }
        }
        .navigationTitle(Nation.namedTitle(nation))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Picker("Category", selection: $category) {
                ForEach(RaceCategory.withStandings) { Text($0.title).tag($0) }
            }
            FavoriteButton(kind: .nation, key: nation, name: Nation.localizedName(nation), nation: nation)
        }
        // As on the standings, only a new category shows the loading state.
        .onChange(of: category) { loader.reset() }
        .task(id: category) { await load() }
        .task { await loadHeadlines() }
    }

    private func load() async {
        await loader.load { try await ibu.worldCupStandings(category: category, discipline: .total, now: .now) }
    }

    private func loadHeadlines() async {
        await headlines.load { try await news.headlines(preferring: Locale.preferredLanguages) }
    }
}
