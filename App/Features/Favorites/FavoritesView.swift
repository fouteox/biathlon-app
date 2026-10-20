import BiathlonKit
import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Query(sort: \Favorite.addedAt) private var favorites: [Favorite]
    @Environment(\.modelContext) private var context
    @Environment(LiveActivities.self) private var liveActivities
    @Environment(LiveActivityStarts.self) private var liveActivityStarts

    var body: some View {
        @Bindable var liveActivityStarts = liveActivityStarts
        List {
            if liveActivities.isAvailable, !favorites.isEmpty {
                Section {
                    Toggle(
                        "Live Activity when a favorite races", systemImage: "dot.radiowaves.left.and.right",
                        isOn: $liveActivityStarts.isEnabled)
                } footer: {
                    Text(
                        "Shows a race on the Lock Screen 30 minutes before the start when one of your favorites is on the start list. Your favorites are sent to the app's server for this."
                    )
                }
            }
            section(.athlete, title: "Biathletes")
            section(.nation, title: "Teams")
        }
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No favorites",
                    systemImage: "star",
                    description: Text(
                        "Tap the star on a biathlete or a team to follow their results from the home screen.")
                )
            }
        }
        .navigationTitle("Favorites")
    }

    @ViewBuilder
    private func section(_ kind: Favorite.Kind, title: LocalizedStringKey) -> some View {
        let items = favorites.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { favorite in
                    row(favorite)
                }
                .onDelete { offsets in
                    for offset in offsets { context.delete(items[offset]) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ favorite: Favorite) -> some View {
        let label = Label {
            Text(favorite.name)
        } icon: {
            NationMark(code: favorite.nation ?? favorite.key)
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
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: matches.isEmpty)
        .accessibilityLabel(matches.isEmpty ? Text("Add to favorites") : Text("Remove from favorites"))
    }
}
