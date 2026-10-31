#if DEBUG
    import Foundation
    import Testing

    @testable import BiathlonKit

    /// The fictional World Cup the UI tests run on: each screen finds what it shows, whatever the date.
    struct SampleDataTests {
        /// Off season, during an event, between two events, and after the last one.
        static let dates = [
            "2026-08-15T12:00:00Z", "2026-12-03T12:00:00Z", "2027-01-20T12:00:00Z", "2027-04-20T12:00:00Z",
        ].map(date)

        @Test(arguments: dates) func homeFeaturesTheNextRaceOrTheLatestResults(now: Date) async throws {
            let feed = try await IBUClient.sample(now: now).homeFeed(now: now)
            #expect(feed.next != nil || feed.latestFinished != nil)
            if let next = feed.next { #expect(next.startTime > now) }
            if let latest = feed.latestFinished {
                #expect(latest.startTime < now)
                #expect(feed.latestResults?.isResult == true)
                #expect(feed.latestResults?.rows.isEmpty == false)
            }
        }

        @Test(arguments: dates) func everyStandingsTableHasRows(now: Date) async throws {
            let client = IBUClient.sample(now: now)
            for category in [RaceCategory.men, .women] {
                for discipline in StandingsDiscipline.allCases {
                    let standings = try await client.worldCupStandings(
                        category: category, discipline: discipline, now: now)
                    let rows = standings.standings.rows
                    #expect(!rows.isEmpty)
                    #expect(rows.allSatisfy { $0.isNation == (discipline == .nations) })
                    #expect(rows.first?.bibColors.isEmpty == false, "The leader wears a bib")
                }
            }
        }

        /// A past season, as the standings' season picker and the calendar show it.
        @Test(arguments: dates) func pastSeasonsHaveFinishedEvents(now: Date) async throws {
            let client = IBUClient.sample(now: now)
            let season = SeasonID.containing(now).previous.previous
            let standings = try await client.worldCupStandings(category: .women, discipline: .sprint, season: season)
            #expect(!standings.standings.rows.isEmpty)
            let events = try await client.events(season: season)
            #expect(!events.isEmpty)
            for event in events {
                let races = try await client.competitions(eventID: event.id)
                #expect(!races.isEmpty)
                #expect(races.allSatisfy { $0.state == .finished && $0.kind != nil && $0.eventID == event.id })
            }
        }

        /// An athlete of the standings opens on a profile, with results in races that are over.
        @Test(arguments: dates) func athletesHaveAProfileAndResults(now: Date) async throws {
            let client = IBUClient.sample(now: now)
            let row = try #require(
                try await client.worldCupStandings(category: .women, discipline: .total, now: now).standings.rows.first)
            let id = try #require(row.athleteID)

            let bio = try await client.athlete(id: id)
            #expect(bio.fullName.isEmpty == false)
            #expect(bio.nation == row.nation)
            #expect(bio.gender == .woman)
            #expect(bio.photoURL == nil, "No photo to download")

            let history = AthleteHistory(results: try await client.athleteResults(id: id), now: now)
            let results = history.results(in: history.initialSeason)
            #expect(!results.isEmpty)
            for result in results {
                let race = try await client.race(id: try #require(result.raceID))
                #expect(race.state == .finished)
                #expect(race.category == .women)
            }
            let standing = try await client.worldCupStanding(of: id, category: .women, season: history.initialSeason)
            #expect(standing != nil)
        }

        /// A nation's screen lists its athletes from the overall standings.
        @Test func nationsHaveAthletes() async throws {
            let now = date("2027-01-20T12:00:00Z")
            let client = IBUClient.sample(now: now)
            let nations = try await client.worldCupStandings(category: .men, discipline: .nations, now: now)
            let overall = try await client.worldCupStandings(category: .men, discipline: .total, now: now)
            for nation in nations.standings.rows {
                #expect(!overall.standings.athletes(of: try #require(nation.nation)).isEmpty)
            }
        }

        /// The calendar's season picker goes back to the 1950s.
        @Test func oldSeasonsAreInTheirYears() async throws {
            let events = try await IBUClient.sample(now: .now).events(season: SeasonID(rawValue: "9899"))
            #expect(events.first?.startDate == date("1998-12-01T12:00:00Z"))
        }

        @Test func racesStillToComeHaveNoResultsYet() async throws {
            let now = date("2026-08-15T12:00:00Z")
            let client = IBUClient.sample(now: now)
            let next = try #require(try await client.homeFeed(now: now).next)
            let results = try await client.results(raceID: next.id)
            #expect(results.competition?.id == next.id)
            #expect(!results.isResult)
            #expect(results.rows.isEmpty)
        }

        @Test func unknownRoutesAreNotFound() async throws {
            await #expect {
                try await IBUClient.sample(now: .now).athlete(id: "BTXXX0")
            } throws: { error in
                guard case IBUError.http(404) = error else { return false }
                return true
            }
        }

        /// Every fictional athlete links to an article, in the app's languages, without the network.
        @Test(arguments: ["en-GB", "fr-FR", "de-DE"])
        func athletesHaveAWikipediaArticle(language: String) async throws {
            let articles = try await WikidataClient.sample.wikipediaArticles(ofAthlete: "BTNORSM01")
            let article = try #require(articles.article(preferring: [language]))
            #expect(article.host() == "\(language.prefix(2)).wikipedia.org")
        }

        /// Every fictional athlete is in a headline, in the app's languages, without the network.
        @Test(arguments: ["en-GB", "fr-FR", "de-DE"])
        func athletesAreInTheNews(language: String) async throws {
            let now = date("2026-12-03T12:00:00Z")
            let headlines = try await NewsClient.sample(now: now).headlines(preferring: [language])
            let standings = try await IBUClient.sample(now: now).worldCupStandings(
                category: .women, discipline: .total, now: now)
            for row in standings.standings.rows {
                let familyName = try #require(row.familyName)
                #expect(headlines.contains { $0.mentions(familyName: familyName) && $0.date != nil })
            }
        }
    }
#endif
