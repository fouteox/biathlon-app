import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// `Fixtures/wikipedia-articles.json` is the Query Service's answer for Julia Simon on 2026-10-28,
/// down to four of her 27 articles.
struct WikidataClientTests {
    static let userAgent = "Biathlon/1.0 (https://github.com/fouteox/biathlon-app)"

    /// A client answering `body` with `status`, which hands each request it gets to `inspect`.
    func client(
        status: Int = 200, body: Data = Data(), inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> WikidataClient {
        WikidataClient(userAgent: Self.userAgent) { request in
            try inspect(request)
            let url = try #require(request.url)
            return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func fixture() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "wikipedia-articles", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Wikimedia asks for a User-Agent naming the app; the athlete is found by their IBU ID, property P2459.
    @Test func asksTheQueryServiceForTheAthletesArticles() async throws {
        let client = client(body: try fixture()) { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "query"
            }
            #expect(url.absoluteString.hasPrefix("https://query.wikidata.org/sparql?"))
            #expect(query?.value?.contains(#"wdt:P2459 "BTFRA20910199601""#) == true)
            #expect(request.value(forHTTPHeaderField: "User-Agent") == Self.userAgent)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/sparql-results+json")
        }
        let articles = try await client.wikipediaArticles(ofAthlete: "BTFRA20910199601")
        #expect(articles.urls.count == 4)
    }

    /// The ID stays a single string in the query, whatever it holds.
    @Test func escapesTheIDInTheQuery() {
        let query = WikidataClient.articlesQuery(ofAthlete: #"A" } \ B"#)
        #expect(query.contains(#"wdt:P2459 "A\" } \\ B" ."#))
    }

    /// The URLs keep their percent-encoding as Wikipedia gives it.
    @Test func decodesEachArticleByLanguage() async throws {
        let articles = try await client(body: try fixture()).wikipediaArticles(ofAthlete: "BTFRA20910199601")
        #expect(articles.urls["fr"] == URL(string: "https://fr.wikipedia.org/wiki/Julia_Simon"))
        #expect(articles.urls["en"] == URL(string: "https://en.wikipedia.org/wiki/Julia_Simon_(biathlete)"))
        #expect(articles.urls["nb"] == URL(string: "https://no.wikipedia.org/wiki/Julia_Simon"))
    }

    /// An athlete Wikidata doesn't know, or without an article, has none.
    @Test func anUnknownAthleteHasNoArticle() async throws {
        let body = Data(#"{"head":{"vars":["article","language"]},"results":{"bindings":[]}}"#.utf8)
        let articles = try await client(body: body).wikipediaArticles(ofAthlete: "BTXXX00000000000")
        #expect(articles.urls.isEmpty)
        #expect(articles.article(preferring: ["fr-FR"]) == nil)
    }

    @Test func aFailedLoadCarriesTheStatus() async {
        let error = await #expect(throws: WikidataError.self) {
            try await client(status: 429).wikipediaArticles(ofAthlete: "BTFRA20910199601")
        }
        guard case .http(429)? = error else {
            Issue.record("Expected an HTTP error, got \(String(describing: error))")
            return
        }
    }

    /// The reader's languages in their order, then English; Norwegian Bokmål's Wikipedia is `nb` too.
    @Test(arguments: [
        (["fr-FR", "en-GB"], "https://fr.wikipedia.org/wiki/Julia_Simon"),
        (["de"], "https://de.wikipedia.org/wiki/Julia_Simon"),
        (["nb-NO"], "https://no.wikipedia.org/wiki/Julia_Simon"),
        (["ja-JP", "de-DE"], "https://de.wikipedia.org/wiki/Julia_Simon"),
        (["ja-JP"], "https://en.wikipedia.org/wiki/Julia_Simon_(biathlete)"),
    ])
    func picksTheReadersLanguage(languages: [String], expected: String) async throws {
        let articles = try await client(body: try fixture()).wikipediaArticles(ofAthlete: "BTFRA20910199601")
        #expect(articles.article(preferring: languages) == URL(string: expected))
    }

    /// Without an article in their languages or in English, the reader gets none.
    @Test func noArticleInTheReadersLanguagesNorInEnglish() {
        let articles = WikipediaArticles(urls: ["de": URL(string: "https://de.wikipedia.org/wiki/A")!])
        #expect(articles.article(preferring: ["fr-FR"]) == nil)
    }
}
