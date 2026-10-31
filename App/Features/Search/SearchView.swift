import BiathlonKit
import SwiftUI

/// Athletes, active or former, by the start of their names, from the IBU's own search.
struct SearchView: View {
    @Environment(\.ibu) private var ibu
    @State private var text = ""
    @State private var loader = Loader<[AthleteMatch]>()

    /// The text without its surrounding spaces: a space typed after a word searches nothing new.
    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search for a biathlete", systemImage: "magnifyingglass",
                    description: Text("Type the start of a first or last name."))
            } else {
                LoadableView(state: loader.state, retry: search) { athletes in
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
        .onChange(of: query) { loader.reset() }
        .task(id: query) {
            guard !query.isEmpty else { return }
            // A pause in the typing, so that each letter typed doesn't reach the IBU.
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await search()
        }
    }

    private func search() async {
        await loader.load { try await ibu.searchAthletes(query) }
    }
}
