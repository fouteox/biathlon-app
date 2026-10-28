#if DEBUG
    import Foundation

    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif

    extension WikidataClient {
        /// A client answering without the network, for `IBUClient.sample`'s fictional athletes: Wikipedia
        /// has no article on them, so each links to the article on biathlon, in English, French and German.
        public static let sample = WikidataClient(userAgent: "") { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let bindings = ["en", "fr", "de"].map { language in
                [
                    "article": ["value": "https://\(language).wikipedia.org/wiki/Biathlon"],
                    "language": ["value": language],
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: ["results": ["bindings": bindings]])
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
#endif
