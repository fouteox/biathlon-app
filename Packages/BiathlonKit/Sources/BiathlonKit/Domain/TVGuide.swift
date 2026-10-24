import Foundation

/// Who shows the races on TV, by country and period: the server's `/v1/tv-coverage`,
/// which keeps it by hand from the broadcasters' announcements.
public struct TVGuide: Decodable, Sendable {
    /// A broadcaster of a country, from `from` (included) to `until` (excluded).
    public struct Coverage: Decodable, Sendable, Hashable {
        /// ISO 3166 code.
        public let country: String
        public let broadcaster: String
        /// Where the broadcaster streams live.
        public let url: URL
        public let from: Date
        public let until: Date
    }

    /// A country's broadcasters for one race.
    public struct Listing: Sendable, Hashable, Identifiable {
        public let country: String
        public let broadcasters: [Coverage]
        public var id: String { country }
    }

    public let coverage: [Coverage]

    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(Self.self, from: json)
    }

    /// The countries with a broadcaster at `start`, in the guide's order, `firstCountry`
    /// (the viewer's region) on top: every country shows, whatever the app's language.
    public func listings(at start: Date, firstCountry: String?) -> [Listing] {
        let airing = coverage.filter { $0.from <= start && start < $0.until }
        let countries = airing.map(\.country).reduce(into: [String]()) { countries, country in
            if !countries.contains(country) { countries.append(country) }
        }
        let ordered = countries.filter { $0 == firstCountry } + countries.filter { $0 != firstCountry }
        return ordered.map { country in
            Listing(country: country, broadcasters: airing.filter { $0.country == country })
        }
    }
}
