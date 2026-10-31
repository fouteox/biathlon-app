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
                .environment(appDelegate.settingsPresentation)
                .environment(appDelegate.liveActivities)
                .environment(appDelegate.liveActivityStarts)
                .environment(\.ibu, appDelegate.client)
                .environment(\.server, appDelegate.server)
                .environment(\.wikidata, appDelegate.wikidata)
                .environment(\.news, appDelegate.news)
                // Cancelled and run again at each change of phase.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    // Start times can move: rebuild the local reminders whenever the app comes back.
                    appDelegate.refreshReminders()
                    await appDelegate.liveActivities.reconcileWhileActive()
                }
        }
        .modelContainer(for: Favorite.self, inMemory: appDelegate.runsOnSampleData)
    }
}

extension EnvironmentValues {
    /// The app injects the delegate's client, so screens and reminders share one.
    @Entry var ibu = IBUClient()
    /// The notification server, `nil` for a build without one.
    @Entry var server: ServerClient? = nil
    /// Finds the athletes' Wikipedia articles.
    @Entry var wikidata = WikidataClient(userAgent: Bundle.main.wikimediaUserAgent)
    /// Reads the outlets' headlines.
    @Entry var news = NewsClient()
}

struct RootView: View {
    @Environment(LiveActivityStarts.self) private var liveActivityStarts
    @Environment(SettingsPresentation.self) private var settingsPresentation
    @Environment(\.scenePhase) private var scenePhase
    @Query private var favorites: [Favorite]

    var body: some View {
        @Bindable var settingsPresentation = settingsPresentation
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
        // Here rather than in Home, so the system can open it whichever tab is selected.
        .sheet(isPresented: $settingsPresentation.isPresented) {
            NavigationStack { SettingsView() }
        }
        // At launch, whenever the races, the favorites, the setting or the token change, wherever
        // in the app, and when the app comes back, for a sync that failed. A change cancels the
        // sync still waiting, which coalesces quick successive ones.
        .task(id: scenePhase == .active ? registration : nil) {
            guard scenePhase == .active else { return }
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
