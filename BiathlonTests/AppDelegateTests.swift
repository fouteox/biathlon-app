import BiathlonKit
import Foundation
import Observation
import Testing
import UserNotifications

@testable import Biathlon

struct AppDelegateTests {
    /// The button iOS shows in Settings > Notifications > Biathlon Live opens the app's settings.
    @Test(.timeLimit(.minutes(1))) func showsTheSettingsWhenTheSystemAsks() async {
        let delegate = AppDelegate()
        delegate.userNotificationCenter(.current(), openSettingsFor: nil)

        for await isPresented in Observations({ delegate.settingsPresentation.isPresented }) where isPresented {
            break
        }
        #expect(delegate.settingsPresentation.isPresented)
    }

    /// IBU data goes through the server's cache.
    @Test func readsThroughTheServer() {
        let (ibu, server) = AppDelegate.clients(sampleData: false)
        #expect(server?.baseURL == Bundle.main.serverURL)
        #expect(ibu.baseURL == Bundle.main.serverURL?.appending(path: "ibu/"))
    }

    /// As the UI tests launch the app: fictional data, and no server to reach.
    @Test func sampleDataNeedsNoNetwork() async throws {
        #expect(AppDelegate.asksForSampleData(arguments: ["Biathlon", "--sample-data"]))
        #expect(!AppDelegate.asksForSampleData(arguments: ["Biathlon"]))
        let (ibu, server) = AppDelegate.clients(sampleData: true)
        #expect(server == nil)
        let standings = try await ibu.worldCupStandings(category: .men, discipline: .total, now: .now)
        #expect(!standings.standings.rows.isEmpty)
        let athlete = try #require(standings.standings.rows.first?.athleteID)
        let articles = try await AppDelegate.wikidata(sampleData: true).wikipediaArticles(ofAthlete: athlete)
        #expect(!articles.urls.isEmpty)
    }
}
