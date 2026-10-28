import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Client for the Wikidata Query Service, which finds an athlete's Wikipedia articles from their
/// IBU ID: Wikidata's property P2459, "IBU biathlete ID". Wikidata's data is CC0.
///
/// Wikimedia asks every client for a User-Agent naming it, with a way to reach its developer
/// (https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy). Each
/// device sends its own requests: the Query Service limits each User-Agent and IP
/// (https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual#Query_limits).
public struct WikidataClient: Sendable {
    public static let endpoint = URL(string: "https://query.wikidata.org/sparql")!

    private let userAgent: String
    private let transport: HTTPTransport

    public init(userAgent: String, transport: @escaping HTTPTransport = URLSession.shared.transport) {
        self.userAgent = userAgent
        self.transport = transport
    }

    public func wikipediaArticles(ofAthlete ibuID: String) async throws -> WikipediaArticles {
        var request = URLRequest(
            url: Self.endpoint.appending(queryItems: [
                URLQueryItem(name: "query", value: Self.articlesQuery(ofAthlete: ibuID))
            ]))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw WikidataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw WikidataError.http(http.statusCode) }
        return try JSONDecoder().decode(WikipediaArticles.self, from: data)
    }

    /// The athlete's articles in every Wikipedia, with each Wikipedia's language code.
    static func articlesQuery(ofAthlete ibuID: String) -> String {
        // A SPARQL string escapes its backslashes and quotes.
        let literal = ibuID.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return """
            SELECT ?article ?language WHERE { \
            ?athlete wdt:P2459 "\(literal)" . \
            ?article schema:about ?athlete ; schema:inLanguage ?language ; \
            schema:isPartOf/wikibase:wikiGroup "wikipedia" . }
            """
    }
}

/// An athlete's Wikipedia articles.
public struct WikipediaArticles: Equatable, Sendable {
    /// Each article, by its Wikipedia's language code (`fr`, `de`, `nb`…).
    public let urls: [String: URL]

    public init(urls: [String: URL]) {
        self.urls = urls
    }

    /// The article in the first of `languages` (`Locale.preferredLanguages`) that has one, else in English.
    public func article(preferring languages: [String]) -> URL? {
        let codes = languages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier } + ["en"]
        return codes.lazy.compactMap { urls[$0] }.first
    }
}

extension WikipediaArticles: Decodable {
    /// A SPARQL result, as https://www.w3.org/TR/sparql11-results-json/ lays it out.
    private struct Results: Decodable {
        struct Bindings: Decodable {
            let bindings: [Binding]
        }
        struct Binding: Decodable {
            let article: Value
            let language: Value
        }
        struct Value: Decodable {
            let value: String
        }
        let results: Bindings
    }

    public init(from decoder: any Decoder) throws {
        let bindings = try Results(from: decoder).results.bindings
        urls = Dictionary(
            bindings.compactMap { binding in URL(string: binding.article.value).map { (binding.language.value, $0) } },
            uniquingKeysWith: { first, _ in first })
    }
}

/// Failures of the Wikidata Query Service. The athlete's screen then goes without the link.
public enum WikidataError: Error {
    case invalidResponse
    case http(Int)
}
