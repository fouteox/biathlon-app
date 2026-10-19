import Foundation

/// World Cup standings identifiers.
public enum Cup {
    /// World Cup standings ID, for example `BT2627SWRLCP__SMTS` for the
    /// men's overall standings of 2026-27.
    public static func worldCupID(_ season: SeasonID, category: RaceCategory, discipline: StandingsDiscipline) -> String
    {
        "BT\(season.rawValue)SWRLCP__\(category.rawValue)\(discipline.rawValue)"
    }
}

/// The standings tables of a World Cup season (last part of the cup ID).
public enum StandingsDiscipline: String, CaseIterable, Identifiable, Sendable {
    case total = "TS"
    case sprint = "SP"
    case pursuit = "PU"
    case individual = "IN"
    case massStart = "MS"
    case nations = "NC"

    public var id: String { rawValue }
}

/// Response of `CupResults?CupId=`.
public struct CupStandings: Decodable, Sendable {
    public let asOf: String?
    public let rows: [CupRow]

    enum CodingKeys: String, CodingKey {
        case asOf = "AsOf"
        case rows = "Rows"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decodeLooseString(forKey: .asOf)
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
