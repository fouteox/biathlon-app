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
                .environment(appDelegate.homeFeed)
                .environment(\.ibu, appDelegate.client)
                .environment(\.server, appDelegate.server)
                .environment(\.wikidata, appDelegate.wikidata)
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
}

struct RootView: View {
    @Environment(LiveActivityStarts.self) private var liveActivityStarts
    @Environment(SettingsPresentation.self) private var settingsPresentation
    @Environment(HomeFeedStore.self) private var homeFeed
    @Environment(\.scenePhase) private var scenePhase
    @Query private var favorites: [Favorite]
    @State private var selectedTab = Screen.home
    /// The live race opened from the accessory, over whichever tab is selected.
    @State private var presentedRace: Competition?
    /// The Home tab's stack, which a link from the widget or the Live Activity opens a race on.
    @State private var homePath: [Route] = []

    private enum Screen: Hashable {
        case home, calendar, standings, favorites, search
    }

    var body: some View {
        @Bindable var settingsPresentation = settingsPresentation
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: Screen.home) {
                NavigationStack(path: $homePath) { HomeView().navigationDestinations() }
            }
            Tab("Calendar", systemImage: "calendar", value: Screen.calendar) {
                NavigationStack { CalendarView().navigationDestinations() }
            }
            Tab("Standings", systemImage: "list.number", value: Screen.standings) {
                NavigationStack { StandingsView().navigationDestinations() }
            }
            Tab("Favorites", systemImage: "star", value: Screen.favorites) {
                NavigationStack { FavoritesView().navigationDestinations() }
            }
            Tab(value: Screen.search, role: .search) {
                NavigationStack { SearchView().navigationDestinations() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // The race being run, reachable from every tab.
        .tabViewBottomAccessory(isEnabled: homeFeed.live != nil) {
            if let live = homeFeed.live {
                LiveRaceAccessory(race: live.race, results: live.results) { presentedRace = live.race }
            }
        }
        .sheet(item: $presentedRace) { race in
            NavigationStack {
                RaceView(race: race)
                    .navigationDestinations()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { presentedRace = nil }
                        }
                    }
            }
        }
        // The feed loads once for the app, and keeps refreshing while a race is live, whichever
        // tab is open: the accessory and Home read the same one.
        .task { await homeFeed.load() }
        .refreshingWhileLive(homeFeed.live != nil, action: homeFeed.load)
        // From the widget or the Live Activity: the race, on the Home tab the app starts on.
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            // Over a sheet left open, the settings or a live race, the race would not show.
            settingsPresentation.isPresented = false
            presentedRace = nil
            selectedTab = .home
            homePath = [link.route]
        }
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
