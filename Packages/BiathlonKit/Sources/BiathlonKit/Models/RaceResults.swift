import Foundation

/// Response of `Results?RaceId=`: start list before the race, results after.
public struct RaceResults: Decodable, Sendable {
    public let raceID: String
    public let isStartList: Bool
    public let isResult: Bool
    public let competition: Competition?
    public let rows: [ResultRow]

    enum CodingKeys: String, CodingKey {
        case raceID = "RaceId"
        case isStartList = "IsStartList"
        case isResult = "IsResult"
        case competition = "Competition"
        case rows = "Results"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceID = try c.decode(String.self, forKey: .raceID)
        isStartList = try c.decodeIfPresent(Bool.self, forKey: .isStartList) ?? false
        isResult = try c.decodeIfPresent(Bool.self, forKey: .isResult) ?? false
        competition = try c.decodeIfPresent(Competition.self, forKey: .competition)
        rows = try c.decodeIfPresent([ResultRow].self, forKey: .rows) ?? []
    }

    /// For a relay, team rows only; otherwise every row.
    public var standings: [ResultRow] {
        let teams = rows.filter(\.isTeam)
        return teams.isEmpty ? rows : teams
    }

    public func legs(of team: ResultRow) -> [ResultRow] {
        rows.filter { !$0.isTeam && $0.teamID != nil && $0.teamID == team.teamID }
    }
}

public struct ResultRow: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { "\(teamID ?? "")-\(athleteID ?? name)-\(leg ?? 0)" }

    public let resultOrder: Int?
    public let athleteID: String?
    public let isTeam: Bool
    public let teamID: String?
    public let name: String
    public let shortName: String?
    public let nation: String?
    public let bib: String?
    public let leg: Int?
    public let rank: String?
    public let shootings: String?
    public let shootingTotal: String?
    public let totalTime: String?
    public let behind: String?
    /// `DNF`, `DNS`, `DSQ`, `LAP`…
    public let irm: String?

    enum CodingKeys: String, CodingKey {
        case resultOrder = "ResultOrder"
        case athleteID = "IBUId"
        case isTeam = "IsTeam"
        case teamID = "TeamId"
        case name = "Name"
        case shortName = "ShortName"
        case nation = "Nat"
        case bib = "Bib"
        case leg = "Leg"
        case rank = "Rank"
        case shootings = "Shootings"
        case shootingTotal = "ShootingTotal"
        case totalTime = "TotalTime"
        case behind = "Behind"
        case irm = "IRM"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resultOrder = try c.decodeLooseInt(forKey: .resultOrder)
        athleteID = try c.decodeIfPresent(String.self, forKey: .athleteID)
        isTeam = try c.decodeIfPresent(Bool.self, forKey: .isTeam) ?? false
        teamID = try c.decodeLooseString(forKey: .teamID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        bib = try c.decodeLooseString(forKey: .bib)
        leg = try c.decodeLooseInt(forKey: .leg)
        rank = try c.decodeLooseString(forKey: .rank)
        shootings = try c.decodeIfPresent(String.self, forKey: .shootings)
        shootingTotal = try c.decodeIfPresent(String.self, forKey: .shootingTotal)
        totalTime = try c.decodeIfPresent(String.self, forKey: .totalTime)
        behind = try c.decodeIfPresent(String.self, forKey: .behind)
        irm = try c.decodeIfPresent(String.self, forKey: .irm)
    }

    /// Number of misses, derived from `ShootingTotal` (`0+2` → 2 spare rounds
    /// for a relay; `2` for an individual race).
    public var misses: Int? {
        guard let shootingTotal else { return nil }
        let parts = shootingTotal.split(separator: "+").compactMap { Int($0) }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}
