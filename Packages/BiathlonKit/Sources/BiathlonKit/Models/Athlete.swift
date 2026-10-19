import Foundation

/// Fiche athlète, issue de `CISBios?IBUId=`. On ne décode que ce que l'app affiche.
public struct AthleteBio: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let fullName: String
    public let familyName: String?
    public let givenName: String?
    public let nation: String?
    /// Date sans heure renvoyée à minuit UTC : l'afficher en UTC
    /// (`Date.FormatStyle` avec `timeZone = .gmt`) pour ne pas décaler le jour.
    public let birthdate: Date?
    public let photoURL: URL?
    public let flagURL: URL?

    enum CodingKeys: String, CodingKey {
        case id = "IBUId"
        case fullName = "FullName"
        case familyName = "FamilyName"
        case givenName = "GivenName"
        case nation = "NAT"
        case birthdate = "Birthdate"
        case photoURL = "PhotoURI"
        case flagURL = "FlagURI"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
            ?? [givenName, familyName].compactMap(\.self).joined(separator: " ")
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        birthdate = try? c.decodeIfPresent(Date.self, forKey: .birthdate)
        photoURL = (try? c.decodeIfPresent(String.self, forKey: .photoURL)).flatMap { URL(string: $0) }
        flagURL = (try? c.decodeIfPresent(String.self, forKey: .flagURL)).flatMap { URL(string: $0) }
    }
}

/// Une ligne de `AllResults?IBUId=` : l'historique d'un athlète.
public struct AthleteResult: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { raceID ?? "\(season ?? "")-\(competition ?? "")-\(place ?? "")" }

    public let raceID: String?
    public let season: String?
    public let competition: String?
    public let place: String?
    public let rank: String?
    public let level: Int?

    enum CodingKeys: String, CodingKey {
        case raceID = "RaceId"
        case season = "Season"
        case competition = "Comp"
        case place = "Place"
        case rank = "Rank"
        case level = "Level"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceID = try c.decodeIfPresent(String.self, forKey: .raceID)
        season = try c.decodeLooseString(forKey: .season)
        competition = try c.decodeIfPresent(String.self, forKey: .competition)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        rank = try c.decodeLooseString(forKey: .rank)
        level = try c.decodeLooseInt(forKey: .level)
    }
}
