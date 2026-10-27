import Foundation

/// Response of `Results?RaceId=`: start list before the race, results after.
public struct RaceResults: Decodable, Sendable {
    public let isStartList: Bool
    public let isResult: Bool
    public let competition: Competition?
    /// The event the race belongs to, where it is held.
    public let event: BiathlonEvent?
    public let rows: [ResultRow]

    enum CodingKeys: String, CodingKey {
        case isStartList = "IsStartList"
        case isResult = "IsResult"
        case competition = "Competition"
        case event = "SportEvt"
        case rows = "Results"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isStartList = try c.decodeIfPresent(Bool.self, forKey: .isStartList) ?? false
        isResult = try c.decodeIfPresent(Bool.self, forKey: .isResult) ?? false
        competition = try c.decodeIfPresent(Competition.self, forKey: .competition)
        event = try c.decodeIfPresent(BiathlonEvent.self, forKey: .event)
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

    public let athleteID: String?
    public let isTeam: Bool
    public let teamID: String?
    public let name: String
    public let shortName: String?
    public let nation: String?
    public let leg: Int?
    public let rank: String?
    public let shootings: String?
    public let totalTime: String?
    public let behind: String?
    /// `DNF`, `DNS`, `DSQ`, `LAP`…
    public let irm: String?

    enum CodingKeys: String, CodingKey {
        case athleteID = "IBUId"
        case isTeam = "IsTeam"
        case teamID = "TeamId"
        case name = "Name"
        case shortName = "ShortName"
        case nation = "Nat"
        case leg = "Leg"
        case rank = "Rank"
        case shootings = "Shootings"
        case totalTime = "TotalTime"
        case behind = "Behind"
        case irm = "IRM"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try c.decodeIfPresent(String.self, forKey: .athleteID)
        isTeam = try c.decodeIfPresent(Bool.self, forKey: .isTeam) ?? false
        teamID = try c.decodeLooseString(forKey: .teamID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        leg = try c.decodeLooseInt(forKey: .leg)
        rank = try c.decodeLooseString(forKey: .rank)
        shootings = try c.decodeIfPresent(String.self, forKey: .shootings)
        totalTime = try c.decodeIfPresent(String.self, forKey: .totalTime)
        behind = try c.decodeIfPresent(String.self, forKey: .behind)
        irm = try c.decodeIfPresent(String.self, forKey: .irm)
    }
}
