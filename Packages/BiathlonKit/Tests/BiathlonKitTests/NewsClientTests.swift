import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// `Fixtures/news-feed.xml` has the shape of the RSS 2.0 feeds of Nordic Magazine, the Sportschau and
/// FasterSkier, with fictional headlines.
struct NewsClientTests {
    static let french = NewsSource(
        name: "Nordic News", feed: URL(string: "https://news.example.com/feed/")!, language: "fr")
    static let english = NewsSource(
        name: "Ski News", feed: URL(string: "https://ski.example.com/feed/")!, language: "en")

    func fixture() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "news-feed", withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A client answering every feed with the fixture, which records the feeds it was asked for.
    func client(sources: [NewsSource], requested: Requested = Requested()) throws -> NewsClient {
        let body = try fixture()
        return NewsClient(sources: sources) { request in
            let url = try #require(request.url)
            await requested.add(url)
            return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    actor Requested {
        private(set) var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }

    @Test func readsTheTitleLinkDateAndSourceOfEachItem() async throws {
        let headlines = try await client(sources: [Self.french]).headlines(preferring: ["fr-FR"])
        #expect(
            headlines.map(\.title) == [
                "Biathlon : Ingrid Solberg s’impose à domicile",
                "Hugo Martel & the relay: a summer in Prémanon",
                "Cross-country: the new season's calendar",
            ])
        let first = try #require(headlines.first)
        #expect(first.url == URL(string: "https://news.example.com/solberg-home-win/"))
        #expect(first.date == date("2026-10-28T16:11:02Z"))
        #expect(first.source == "Nordic News")
        #expect(headlines[1].date == date("2026-10-27T17:59:18Z"))
        #expect(headlines[2].date == date("2026-10-05T08:41:08Z"))
    }

    /// The reader's first language that has a source, else English; never the others.
    @Test(arguments: [
        (["fr-FR", "en-GB"], "https://news.example.com/feed/"),
        (["de-DE", "fr-FR"], "https://news.example.com/feed/"),
        (["ja-JP"], "https://ski.example.com/feed/"),
    ])
    func readsTheFeedsInTheReadersLanguage(languages: [String], feed: String) async throws {
        let requested = Requested()
        _ = try await client(sources: [Self.french, Self.english], requested: requested)
            .headlines(preferring: languages)
        #expect(await requested.urls == [URL(string: feed)!])
    }

    @Test func newestFirstAcrossSources() async throws {
        let other = NewsSource(name: "Other", feed: URL(string: "https://other.example.com/feed")!, language: "fr")
        let headlines = try await client(sources: [Self.french, other]).headlines(preferring: ["fr"])
        #expect(headlines.count == 6)
        #expect(headlines.map(\.date) == headlines.map(\.date).sorted { ($0 ?? .distantPast) > ($1 ?? .distantPast) })
    }

    @Test func aFailedFeedCarriesTheStatus() async {
        let client = NewsClient(sources: [Self.french]) { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        let error = await #expect(throws: NewsError.self) { try await client.headlines(preferring: ["fr"]) }
        guard case .http(503)? = error else {
            Issue.record("Expected an HTTP error, got \(String(describing: error))")
            return
        }
    }

    /// A family name matches whole words of the title or of the article's tags, whatever their case and accents.
    @Test(arguments: [
        ("SOLBERG", ["solberg-home-win"]), ("MARTEL", ["martel-relay"]), ("PREMANON", ["martel-relay"]),
        ("Solb", []),
    ])
    func findsTheHeadlinesNamingAnAthlete(familyName: String, articles: [String]) async throws {
        let headlines = try await client(sources: [Self.french]).headlines(preferring: ["fr"])
        #expect(headlines.filter { $0.mentions(familyName: familyName) }.map(\.url.lastPathComponent) == articles)
    }

    /// The IBU writes Nordic and German letters as two (`LAEGREID`, `OEBERG`), or drops their accents
    /// (`MAKARAINEN`); the outlets keep them.
    @Test(arguments: [
        ("Sturla Holm Lægreid wins in Kontiolahti", "LAEGREID"),
        ("Hanna Öberg back on the podium", "OEBERG"),
        ("Johannes Thingnes Bø retires", "THINGNES BOE"),
        ("Kaisa Mäkäräinen, ten years later", "MAKARAINEN"),
        ("Franziska Preuß in yellow", "PREUSS"),
    ])
    func matchesTheIBUSpellingOfNordicAndGermanLetters(title: String, familyName: String) {
        let headline = Headline(
            title: title, url: URL(string: "https://e.com")!, date: nil, source: "S", categories: [])
        #expect(headline.mentions(familyName: familyName))
    }

    @Test func aFamilyNameCanHaveSeveralWords() {
        let headline = Headline(
            title: "Dorothea Wierer and Lisa Vittozzi on the podium", url: URL(string: "https://e.com")!,
            date: nil, source: "S", categories: ["Johannes Thingnes Bø"])
        #expect(headline.mentions(familyName: "THINGNES BOE"))
        #expect(headline.mentions(familyName: "Wierer"))
        #expect(!headline.mentions(familyName: "WIERER LISA"))
        #expect(!headline.mentions(familyName: ""))
    }
}
