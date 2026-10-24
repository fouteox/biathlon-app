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

    /// The broadcasters of a race: the viewer's own country apart, the others in the guide's order.
    public struct Listings: Sendable, Hashable {
        public let home: Listing?
        public let others: [Listing]
        public var isEmpty: Bool { home == nil && others.isEmpty }
    }

    /// The countries with a broadcaster at `start`, `home` (the viewer's region) set apart
    /// from the others, which every viewer can still look up, whatever the app's language.
    public func listings(at start: Date, home: String?) -> Listings {
        let airing = coverage.filter { $0.from <= start && start < $0.until }
        let countries = airing.map(\.country).reduce(into: [String]()) { countries, country in
            if !countries.contains(country) { countries.append(country) }
        }
        let listings = countries.map { country in
            Listing(country: country, broadcasters: airing.filter { $0.country == country })
        }
        return Listings(home: listings.first { $0.country == home }, others: listings.filter { $0.country != home })
    }
}
