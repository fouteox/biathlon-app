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
                .environment(appDelegate.liveActivities)
                .environment(\.ibu, appDelegate.client)
        }
        .modelContainer(for: Favorite.self)
        .onChange(of: scenePhase) { _, phase in
            // Start times can move: rebuild the local reminders whenever the app comes back.
            if phase == .active { appDelegate.refreshReminders() }
        }
    }
}

extension EnvironmentValues {
    /// The app injects the delegate's client, so screens and reminders share one.
    @Entry var ibu = IBUClient()
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack { HomeView().navigationDestinations() }
            }
            Tab("Calendar", systemImage: "calendar") {
                NavigationStack { CalendarView().navigationDestinations() }
            }
            Tab("Standings", systemImage: "list.number") {
                NavigationStack { StandingsView().navigationDestinations() }
            }
            Tab("Favorites", systemImage: "star") {
                NavigationStack { FavoritesView().navigationDestinations() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
