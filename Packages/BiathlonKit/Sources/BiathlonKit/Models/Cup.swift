import Foundation

/// A standings table available for a season, from `Cups?SeasonId=`.
public struct Cup: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let description: String
    public let level: Int?

    enum CodingKeys: String, CodingKey {
        case id = "CupId"
        case description = "Description"
        case level = "Level"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? id
        level = try c.decodeLooseInt(forKey: .level)
    }

    public init(id: String, description: String, level: Int? = nil) {
        self.id = id
        self.description = description
        self.level = level
    }

    /// Biathlon (`BT`) rather than para-biathlon (`PB`).
    public var isBiathlon: Bool { id.hasPrefix("BT") }
    public var isWorldCup: Bool { id.contains("SWRLCP") }

    /// The last four characters: `SMTS` (men's overall), `SWSP`
    /// (women's sprint), `MXRL` (mixed relay)…
    public var discipline: String { String(id.suffix(4)) }
    public var isMen: Bool { discipline.hasPrefix("SM") }
    public var isWomen: Bool { discipline.hasPrefix("SW") }
}

extension Cup {
    /// World Cup standings ID for a season, for example
    /// `worldCupID(.current, "SMTS")` → `BT2627SWRLCP__SMTS`.
    public static func worldCupID(_ season: SeasonID, _ discipline: String) -> String {
        "BT\(season.rawValue)SWRLCP__\(discipline)"
    }
}

/// Response of `CupResults?CupId=`.
public struct CupStandings: Decodable, Sendable {
    public let cupID: String
    public let name: String
    public let asOf: String?
    public let raceCount: Int?
    public let totalRaces: Int?
    public let rows: [CupRow]

    enum CodingKeys: String, CodingKey {
        case cupID = "CupId"
        case name = "CupName"
        case asOf = "AsOf"
        case raceCount = "RaceCount"
        case totalRaces = "TotalRaces"
        case rows = "Rows"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cupID = try c.decode(String.self, forKey: .cupID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? cupID
        asOf = try c.decodeLooseString(forKey: .asOf)
        raceCount = try c.decodeLooseInt(forKey: .raceCount)
        totalRaces = try c.decodeLooseInt(forKey: .totalRaces)
        rows = try c.decodeIfPresent([CupRow].self, forKey: .rows) ?? []
    }
}

public struct CupRow: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { athleteID ?? "\(nation ?? "")-\(name)" }

    public let rank: String?
    public let athleteID: String?
    public let name: String
    public let shortName: String?
    public let nation: String?
    public let score: String?
    /// Change since the last race: negative = places gained.
    public let rankChange: Int?
    public let bibColors: [String]

    enum CodingKeys: String, CodingKey {
        case rank = "Rank"
        case athleteID = "IBUId"
        case name = "Name"
        case shortName = "ShortName"
        case nation = "Nat"
        case score = "Score"
        case rankChange = "RnkDiff"
        case bibs = "Bibs"
    }

    struct Bib: Decodable {
        let color: String?
        enum CodingKeys: String, CodingKey { case color = "Color" }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decodeLooseString(forKey: .rank)
        athleteID = try c.decodeIfPresent(String.self, forKey: .athleteID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        score = try c.decodeLooseString(forKey: .score)
        rankChange = try c.decodeLooseInt(forKey: .rankChange)
        let bibs = (try? c.decodeIfPresent([Bib].self, forKey: .bibs)) ?? nil
        bibColors = bibs?.compactMap(\.color) ?? []
    }

    /// Nations standings: no `IBUId`, the name is the country.
    public var isNation: Bool { athleteID == nil }
}
