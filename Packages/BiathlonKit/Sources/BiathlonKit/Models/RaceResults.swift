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

    /// The athlete or team ranked first, once anyone is: a start list ranks nobody, and someone
    /// out of the race (DNS, DNF…) leads nobody.
    public var leader: ResultRow? {
        standings.first { $0.rank != nil && $0.irm == nil }
    }

    /// The first three, without the athletes or teams who didn't finish: none before the results.
    public var podium: [ResultRow] {
        isResult ? Array(standings.filter { $0.irm == nil }.prefix(3)) : []
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
    public let familyName: String?
    public let givenName: String?
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
        case familyName = "FamilyName"
        case givenName = "GivenName"
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
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        leg = try c.decodeLooseInt(forKey: .leg)
        rank = try c.decodeLooseString(forKey: .rank)
        shootings = try c.decodeIfPresent(String.self, forKey: .shootings)
        totalTime = try c.decodeIfPresent(String.self, forKey: .totalTime)
        behind = try c.decodeIfPresent(String.self, forKey: .behind)
        irm = try c.decodeIfPresent(String.self, forKey: .irm)
    }
}

extension ResultRow {
    /// The name as a voice reads it: a team by its nation, an athlete given name first and family
    /// name out of capitals, which a voice would spell out ("Johan-Olav Smoerdal Botn").
    public func spokenName(locale: Locale = .current) -> String {
        if isTeam, let nation { return Nation.localizedName(nation, locale: locale) }
        guard let familyName, !familyName.isEmpty else { return name }
        let family = familyName.capitalized(with: locale)
        guard let givenName, !givenName.isEmpty else { return family }
        return "\(givenName) \(family)"
    }
}
