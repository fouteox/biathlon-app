import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Query(sort: \Favorite.addedAt) private var favorites: [Favorite]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            section(.athlete, title: "Biathlètes")
            section(.nation, title: "Équipes")
        }
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "Aucun favori",
                    systemImage: "star",
                    description: Text("Touchez l'étoile d'un biathlète ou d'une équipe pour suivre ses résultats depuis l'accueil.")
                )
            }
        }
        .navigationTitle("Favoris")
    }

    @ViewBuilder
    private func section(_ kind: Favorite.Kind, title: String) -> some View {
        let items = favorites.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { favorite in
                    row(favorite)
                }
                .onDelete { offsets in
                    offsets.map { items[$0] }.forEach { context.delete($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ favorite: Favorite) -> some View {
        let label = Label {
            Text(favorite.name)
        } icon: {
            Text(Nation.flag(favorite.nation ?? favorite.key))
        }
        switch favorite.kind {
        case .athlete:
            NavigationLink(value: Route.athlete(id: favorite.key, name: favorite.name)) { label }
        case .nation:
            label
        }
    }
}

/// Reusable star for detail screens and lists.
struct FavoriteButton: View {
    let kind: Favorite.Kind
    let key: String
    let name: String
    var nation: String?

    @Environment(\.modelContext) private var context
    @Query private var matches: [Favorite]

    init(kind: Favorite.Kind, key: String, name: String, nation: String? = nil) {
        self.kind = kind
        self.key = key
        self.name = name
        self.nation = nation
        let raw = kind.rawValue
        _matches = Query(filter: #Predicate<Favorite> { $0.kindRaw == raw && $0.key == key })
    }

    var body: some View {
        Button {
            context.toggleFavorite(kind, key: key, name: name, nation: nation)
        } label: {
            Image(systemName: matches.isEmpty ? "star" : "star.fill")
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: matches.isEmpty)
        .accessibilityLabel(matches.isEmpty ? "Ajouter aux favoris" : "Retirer des favoris")
    }
}
