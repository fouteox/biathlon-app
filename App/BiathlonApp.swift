import BiathlonKit
import SwiftData
import SwiftUI

@main
struct BiathlonApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.settings)
                .environment(appDelegate.push)
        }
        .modelContainer(for: Favorite.self)
        .onChange(of: scenePhase) { _, phase in
            // Start times can move: rebuild the local reminders whenever the app comes back.
            if phase == .active { Task { await appDelegate.refreshReminders() } }
        }
    }
}

extension EnvironmentValues {
    @Entry var ibu = IBUClient()
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house") {
                NavigationStack { HomeView().navigationDestinations() }
            }
            Tab("Calendrier", systemImage: "calendar") {
                NavigationStack { CalendarView().navigationDestinations() }
            }
            Tab("Classements", systemImage: "list.number") {
                NavigationStack { StandingsView().navigationDestinations() }
            }
            Tab("Favoris", systemImage: "star") {
                NavigationStack { FavoritesView().navigationDestinations() }
            }
        }
    }
}
