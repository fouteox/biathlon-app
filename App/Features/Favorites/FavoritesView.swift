import BiathlonKit
import SwiftData
import SwiftUI
import os

struct FavoritesView: View {
    @Query(sort: \Favorite.addedAt) private var favorites: [Favorite]
    @Environment(\.modelContext) private var context
    @Environment(\.ibu) private var ibu
    @Environment(LiveActivities.self) private var liveActivities
    @Environment(LiveActivityStarts.self) private var liveActivityStarts
    @Environment(\.editMode) private var editMode
    /// Where the favorites stand this season; the rows go without it until it loads, or if it fails.
    @State private var standings = Loader<FavoriteStandings>()

    var body: some View {
        @Bindable var liveActivityStarts = liveActivityStarts
        List {
            // The favorites first, each with its standing: what the tab is for.
            section(.athlete, title: "Biathletes", footer: "Rank and points in the World Cup overall standings.")
            section(.nation, title: "Teams", footer: "Rank in the Nations Cup, men and women.")
            // A setting changed once, below the list. Kept while on, even with Live Activities
            // turned off in Settings: it is how the favorites leave the server.
            if liveActivities.isAvailable || liveActivityStarts.isEnabled, !favorites.isEmpty {
                Section {
                    Toggle(
                        "Live Activity when a favorite races", systemImage: "dot.radiowaves.left.and.right",
                        isOn: $liveActivityStarts.isEnabled)
                } footer: {
                    Text(
                        "Shows the race on the Lock Screen 30 minutes before the start when a favorite is on the start list."
                    )
                }
            }
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
        .toolbar {
            if !favorites.isEmpty {
                EditButton()
            }
        }
        // Deleting the last favorite hides the Edit button: leave edit mode with it, or the
        // next favorite would show up in a list still being edited.
        .onChange(of: favorites.isEmpty) { _, isEmpty in
            if isEmpty { editMode?.wrappedValue = .inactive }
        }
        .task { await refreshAthletes() }
        .task { await standings.load { try await ibu.favoriteStandings(now: .now) } }
    }

    /// Updates the athletes from their IBU profiles; one that fails to load waits for the next visit.
    private func refreshAthletes() async {
        let ids = favorites.filter { $0.kind == .athlete }.map(\.key)
        let ibu = ibu
        await withTaskGroup { group in
            for id in ids {
                group.addTask { () -> (String, Result<AthleteBio, any Error>) in
                    do {
                        return (id, .success(try await ibu.athlete(id: id)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let bio):
                    favorites.first { $0.kind == .athlete && $0.key == id }?.update(from: bio)
                case .failure(let error):
                    Logger.data.error(
                        "Refreshing favorite \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: Favorite.Kind, title: LocalizedStringKey, footer: LocalizedStringKey) -> some View {
        let items = favorites.filter { $0.kind == kind }
        if !items.isEmpty {
            Section {
                ForEach(items) { favorite in
                    row(favorite)
                }
                .onDelete { offsets in
                    for offset in offsets { context.delete(items[offset]) }
                }
            } header: {
                Text(title)
            } footer: {
                if standings.state.value != nil {
                    Text(footer)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ favorite: Favorite) -> some View {
        let label = LabeledContent {
            if let standing = standing(of: favorite) {
                standing.font(.subheadline.monospacedDigit())
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(favorite.title)
                    if favorite.isDeceased {
                        Text(.deceased(favorite.gender)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                NationMark(code: favorite.nation ?? favorite.key)
            }
        }
        .accessibilityElement(children: .combine)
        switch favorite.kind {
        case .athlete:
            NavigationLink(value: Route.athlete(id: favorite.key, name: favorite.name)) { label }
        case .nation:
            NavigationLink(value: Route.nation(code: favorite.key, category: .men)) { label }
        case nil:
            label
        }
    }

    /// Where the favorite stands: an athlete's rank and points, a nation's rank in each Nations Cup.
    private func standing(of favorite: Favorite) -> Text? {
        guard let standings = standings.state.value else { return nil }
        switch favorite.kind {
        case .athlete:
            return standings.standing(ofAthlete: favorite.key)?.rankAndPoints
        case .nation:
            let ranks = standings.standings(ofNation: favorite.key).map { "\($0.category.title) \($0.row.rank ?? "–")" }
            return ranks.isEmpty ? nil : Text(verbatim: ranks.joined(separator: " · "))
        case nil:
            return nil
        }
    }
}

/// Reusable star for detail screens and lists. Its title shows in a list row and reads out
/// with VoiceOver; toolbars and `.labelStyle(.iconOnly)` show the star alone.
struct FavoriteButton: View {
    let kind: Favorite.Kind
    let key: String
    let name: String
    var nation: String?
    /// Named in the title, for a button whose favorite the screen doesn't already show.
    var subject: String?

    @Environment(\.modelContext) private var context
    @Query private var matches: [Favorite]

    init(kind: Favorite.Kind, key: String, name: String, nation: String? = nil, subject: String? = nil) {
        self.kind = kind
        self.key = key
        self.name = name
        self.nation = nation
        self.subject = subject
        let raw = kind.rawValue
        _matches = Query(filter: #Predicate<Favorite> { $0.kindRaw == raw && $0.key == key })
    }

    var body: some View {
        Button {
            context.toggleFavorite(kind, key: key, name: name, nation: nation)
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: matches.isEmpty ? "star" : "star.fill")
            }
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: matches.isEmpty)
    }

    private var title: Text {
        switch (subject, matches.isEmpty) {
        case (nil, true): Text("Add to favorites")
        case (nil, false): Text("Remove from favorites")
        case (let subject?, true): Text("Add \(subject) to favorites")
        case (let subject?, false): Text("Remove \(subject) from favorites")
        }
    }
}
