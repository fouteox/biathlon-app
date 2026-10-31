import BiathlonKit
import SwiftData
import SwiftUI

/// Athletes, active or former, by the start of their names, from the IBU's own search.
struct SearchView: View {
    @Environment(\.ibu) private var ibu
    @Query(sort: \Favorite.addedAt) private var favorites: [Favorite]
    @State private var text = ""
    @State private var loader = Loader<[AthleteMatch]>()
    /// Bumped by "Try again": a retry is a search of its own, which a new query cancels.
    @State private var attempt = 0

    /// The text without its surrounding spaces: a space typed after a word searches nothing new.
    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search for a biathlete", systemImage: "magnifyingglass",
                    description: Text("Type the start of a first or last name."))
            } else {
                LoadableView(state: loader.state, retry: retry) { athletes in
                    if athletes.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        List(athletes) { athlete in
                            NavigationLink(value: Route.athlete(id: athlete.id, name: athlete.name)) {
                                HStack(spacing: 12) {
                                    NationMark(code: athlete.nation)
                                    Text(athlete.name)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $text, prompt: "Biathletes")
        // Before anything is typed, the favorite athletes (HIG Searching: suggestions), who open
        // their profile; while typing, the results take the whole screen.
        .searchSuggestions {
            if query.isEmpty {
                ForEach(favorites.filter { $0.kind == .athlete }) { favorite in
                    NavigationLink(value: Route.athlete(id: favorite.key, name: favorite.name)) {
                        Label {
                            Text(favorite.title)
                        } icon: {
                            NationMark(code: favorite.nation)
                        }
                    }
                }
            }
        }
        .onChange(of: query) { loader.reset() }
        .task(id: Search(query: query, attempt: attempt)) {
            guard !query.isEmpty else { return }
            // A pause in the typing, so that each letter typed doesn't reach the IBU.
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await loader.load { try await ibu.searchAthletes(query) }
        }
    }

    private struct Search: Equatable {
        let query: String
        let attempt: Int
    }

    private func retry() async {
        loader.reset()
        attempt += 1
    }
}
