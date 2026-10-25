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
                .environment(appDelegate.liveActivityStarts)
                .environment(\.ibu, appDelegate.client)
                .environment(\.server, appDelegate.server)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await appDelegate.liveActivities.reconcileWhileActive()
                }
        }
        .modelContainer(for: Favorite.self)
        .onChange(of: scenePhase) { _, phase in
            // Start times can move: rebuild the local reminders whenever the app comes back.
            guard phase == .active else { return }
            appDelegate.refreshReminders()
        }
    }
}

extension EnvironmentValues {
    /// The app injects the delegate's client, so screens and reminders share one.
    @Entry var ibu = IBUClient()
    /// The notification server, `nil` for a build without one.
    @Entry var server: ServerClient? = nil
}

struct RootView: View {
    @Environment(LiveActivityStarts.self) private var liveActivityStarts
    @Query private var favorites: [Favorite]

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
        // At launch, and whenever the favorites, the setting or the token change, wherever in
        // the app. A change cancels the sync still waiting, which coalesces quick successive ones.
        .task(id: registration) {
            let registration = registration
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await liveActivityStarts.sync(registration)
        }
    }

    private var registration: LiveActivityStarts.Registration {
        liveActivityStarts.registration(favorites: FavoriteSet(favorites))
    }
}
