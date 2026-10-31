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

    /// The rows of `nation`'s athletes, in the standings' order. The API lists a nation's
    /// athletes nowhere else: its screen shows those who scored points.
    public func athletes(of nation: String) -> [CupRow] {
        rows.filter { !$0.isNation && $0.nation == nation }
    }
}

public struct CupRow: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { athleteID ?? "\(nation ?? "")-\(name)" }

    public let rank: String?
    public let athleteID: String?
    public let name: String
    public let shortName: String?
    /// In capitals (`SIMON`), as the IBU writes it; `nil` for a nation.
    public let familyName: String?
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
        case familyName = "FamilyName"
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
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        let nation = try c.decodeIfPresent(String.self, forKey: .nation)
        self.nation = nation
        // A nation's row carries its code as `IBUId`.
        athleteID = try c.decodeIfPresent(String.self, forKey: .athleteID).flatMap { $0 == nation ? nil : $0 }
        score = try c.decodeLooseString(forKey: .score)
        rankChange = try c.decodeLooseInt(forKey: .rankChange)
        let bibs = (try? c.decodeIfPresent([Bib].self, forKey: .bibs)) ?? nil
        bibColors = bibs?.compactMap(\.color) ?? []
    }

    /// Nations standings: the `IBUId` is the nation's code, the name is the country in English.
    public var isNation: Bool { athleteID == nil }
}
