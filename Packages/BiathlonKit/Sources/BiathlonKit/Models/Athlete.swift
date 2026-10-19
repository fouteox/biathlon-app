import Foundation

/// Athlete profile, from `CISBios?IBUId=`. Only what the app shows is decoded.
public struct AthleteBio: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let fullName: String
    public let nation: String?
    /// Date without a time, returned at midnight UTC: display it in UTC
    /// (`Date.FormatStyle` with `timeZone = .gmt`) so the day doesn't shift.
    public let birthdate: Date?
    public let photoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id = "IBUId"
        case fullName = "FullName"
        case familyName = "FamilyName"
        case givenName = "GivenName"
        case nation = "NAT"
        case birthdate = "Birthdate"
        case photoURL = "PhotoURI"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        let givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        fullName =
            try c.decodeIfPresent(String.self, forKey: .fullName)
            ?? [givenName, familyName].compactMap(\.self).joined(separator: " ")
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
        birthdate = try? c.decodeIfPresent(Date.self, forKey: .birthdate)
        photoURL = (try? c.decodeIfPresent(String.self, forKey: .photoURL)).flatMap { URL(string: $0) }
    }
}

/// One row of `AllResults?IBUId=`: an athlete's history.
public struct AthleteResult: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { raceID ?? "\(season ?? "")-\(competition ?? "")-\(place ?? "")" }

    public let raceID: String?
    public let season: String?
    public let competition: String?
    public let place: String?
    public let rank: String?

    enum CodingKeys: String, CodingKey {
        case raceID = "RaceId"
        case season = "Season"
        case competition = "Comp"
        case place = "Place"
        case rank = "Rank"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceID = try c.decodeIfPresent(String.self, forKey: .raceID)
        season = try c.decodeLooseString(forKey: .season)
        competition = try c.decodeIfPresent(String.self, forKey: .competition)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        rank = try c.decodeLooseString(forKey: .rank)
    }
}
