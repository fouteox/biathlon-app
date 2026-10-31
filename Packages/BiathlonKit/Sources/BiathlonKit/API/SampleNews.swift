#if DEBUG
    import Foundation

    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif

    extension NewsClient {
        /// A client answering without the network, with fictional headlines about `IBUClient.sample`'s
        /// athletes, one per athlete, in every language.
        public static func sample(now: Date) -> NewsClient {
            let source = { (language: String) in
                NewsSource(
                    name: "Sample News", feed: URL(string: "https://news.example.com/\(language).xml")!,
                    language: language)
            }
            return NewsClient(sources: ["en", "fr", "de"].map(source)) { request in
                guard let url = request.url else { throw URLError(.badURL) }
                // RFC 822, as RSS writes dates.
                let dates = DateFormatter()
                dates.locale = Locale(identifier: "en_US_POSIX")
                dates.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                let items = SampleWorldCup.athleteNames.enumerated().map { index, name in
                    let date = now.addingTimeInterval(-3_600 * Double(index + 1))
                    return """
                        <item><title>\(name.given) \(name.family.capitalized) prepares for the World Cup</title>\
                        <link>https://news.example.com/\(index)</link>\
                        <pubDate>\(dates.string(from: date))</pubDate></item>
                        """
                }
                let feed =
                    #"<?xml version="1.0"?><rss version="2.0"><channel>"#
                    + items.joined() + "</channel></rss>"
                return (
                    Data(feed.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        }
    }
#endif
