import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// A media outlet's RSS 2.0 feed. The app shows only each article's headline, with a link to it.
public struct NewsSource: Hashable, Sendable {
    public let name: String
    public let feed: URL
    /// The language of its articles, a language code (`fr`).
    public let language: String

    public init(name: String, feed: URL, language: String) {
        self.name = name
        self.feed = feed
        self.language = language
    }

    /// One source per language of the app. FasterSkier has no feed of its biathlon articles: the screens
    /// only show the headlines naming their athletes anyway. Shown only once each outlet agrees.
    public static let all = [
        NewsSource(
            name: "Nordic Magazine", feed: URL(string: "https://www.nordicmag.info/category/biathlon/feed/")!,
            language: "fr"),
        NewsSource(
            name: "Sportschau", feed: URL(string: "https://www.sportschau.de/wintersport/biathlon/index~rss2.xml")!,
            language: "de"),
        NewsSource(name: "FasterSkier", feed: URL(string: "https://fasterskier.com/feed.xml")!, language: "en"),
    ]
}

/// An article's headline, which opens the article on its outlet's site.
public struct Headline: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let title: String
    public let url: URL
    public let date: Date?
    /// The outlet's name.
    public let source: String
    /// The item's RSS categories: the outlets tag articles with the athletes they are about.
    let categories: [String]

    /// Whether the title or the tags name `familyName` in whole words, whatever the case and accents:
    /// an IBU family name is in capitals (`THINGNES BØ`).
    public func mentions(familyName: String) -> Bool {
        let name = Self.words(familyName)
        guard !name.isEmpty else { return false }
        return ([title] + categories).contains { text in
            let words = Self.words(text)
            return words.count >= name.count
                && (0...(words.count - name.count)).contains { Array(words[$0..<$0 + name.count]) == name }
        }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter }
            .map(String.init)
    }
}

/// Reads the outlets' RSS feeds.
public struct NewsClient: Sendable {
    private let sources: [NewsSource]
    private let transport: HTTPTransport

    public init(
        sources: [NewsSource] = NewsSource.all, transport: @escaping HTTPTransport = URLSession.shared.transport
    ) {
        self.sources = sources
        self.transport = transport
    }

    /// The headlines of the sources in the reader's first language that has any (`Locale.preferredLanguages`),
    /// else in English, newest first.
    public func headlines(preferring languages: [String]) async throws -> [Headline] {
        let language = readerLanguageCodes(languages).first { code in sources.contains { $0.language == code } }
        let chosen = sources.filter { $0.language == language }
        let headlines = try await withThrowingTaskGroup { group in
            for source in chosen {
                group.addTask { try await headlines(of: source) }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        return headlines.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func headlines(of source: NewsSource) async throws -> [Headline] {
        let (data, response) = try await transport(URLRequest(url: source.feed))
        guard let http = response as? HTTPURLResponse else { throw NewsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NewsError.http(http.statusCode) }
        let items = try RSSItems(data: data).items
        return items.compactMap { item in
            guard let url = URL(string: item.link), !item.title.isEmpty else { return nil }
            return Headline(
                title: item.title, url: url, date: item.date, source: source.name, categories: item.categories)
        }
    }
}

/// Failures of a feed. The screens then go without the headlines.
public enum NewsError: Error {
    case invalidResponse
    case http(Int)
    case unreadableFeed
}

/// The items of an RSS 2.0 feed (https://www.rssboard.org/rss-specification): only what the app shows.
private final class RSSItems: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var date: Date?
        var categories: [String] = []
    }

    private(set) var items: [Item] = []
    private var item: Item?
    private var text = ""
    /// RFC 822 dates, as the RSS specification requires: `Wed, 28 Oct 2026 16:11:02 +0000` or `… GMT`.
    private let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    init(data: Data) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw NewsError.unreadableFeed }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "item" { item = Item() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title": item?.title = value
        case "link": item?.link = value
        case "pubDate": item?.date = dates.date(from: value)
        case "category": item?.categories.append(value)
        case "item":
            if let item { items.append(item) }
            item = nil
        default: break
        }
    }
}
