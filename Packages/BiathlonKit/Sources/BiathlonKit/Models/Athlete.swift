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
    /// `Functions` is "Deceased" instead of "Athlete" once the IBU records an athlete's death
    /// (Sivert Guttorm Bakken, Linas Banys); a retirement isn't recorded.
    public let isDeceased: Bool
    /// `nil` when the IBU doesn't give it.
    public let gender: Gender?

    enum CodingKeys: String, CodingKey {
        case id = "IBUId"
        case fullName = "FullName"
        case familyName = "FamilyName"
        case givenName = "GivenName"
        case nation = "NAT"
        case birthdate = "Birthdate"
        case photoURL = "PhotoURI"
        case functions = "Functions"
        case gender = "GenderId"
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
        isDeceased = try c.decodeIfPresent(String.self, forKey: .functions) == "Deceased"
        gender = try c.decodeIfPresent(String.self, forKey: .gender).flatMap(Gender.init(rawValue:))
    }

    /// The athlete's age on `date`, counted in UTC like the birthdate; `nil` without a birthdate
    /// or once the IBU records their death, as it gives no date of death.
    public func age(on date: Date) -> Int? {
        guard let birthdate, !isDeceased else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.dateComponents([.year], from: birthdate, to: date).year
    }
}

/// An athlete's gender, as `GenderId` gives it.
public enum Gender: String, Sendable {
    case man = "M"
    case woman = "W"

    /// The category of the athlete's standings.
    public var category: RaceCategory {
        switch self {
        case .man: .men
        case .woman: .women
        }
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
    /// The circuit: "WC", "WCH" and "OWG" for the World Cup, the World Championships and the
    /// Olympics, the races of `Events?Level=1`; others for the IBU Cup, juniors or summer events.
    public let level: String?

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
        level = try c.decodeIfPresent(String.self, forKey: .level)
    }

    /// The races the app follows everywhere else.
    var isWorldCupCircuit: Bool { level.map(Self.worldCupLevels.contains) ?? false }

    public var kind: RaceKind? { raceID.flatMap(RaceKind.init(raceID:)) }

    /// The season of `Season`, which reads "25/26" (`SeasonId` comes empty).
    public var seasonID: SeasonID? {
        guard let season, season.wholeMatch(of: /\d\d\/\d\d/) != nil else { return nil }
        return SeasonID(rawValue: season.replacing("/", with: ""))
    }

    private static let worldCupLevels: Set = ["WC", "WCH", "OWG"]
}
