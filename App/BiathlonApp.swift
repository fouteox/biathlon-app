import BiathlonKit
import SwiftData
import SwiftUI

@main
struct BiathlonApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Favorite.self)
    }
}

extension EnvironmentValues {
    @Entry var ibu = IBUClient()
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house") {
                NavigationStack { HomeView() }
            }
            Tab("Calendrier", systemImage: "calendar") {
                NavigationStack { CalendarView() }
            }
            Tab("Classements", systemImage: "list.number") {
                NavigationStack { StandingsView() }
            }
            Tab("Favoris", systemImage: "star") {
                NavigationStack { FavoritesView() }
            }
        }
        .navigationDestinations()
    }
}
