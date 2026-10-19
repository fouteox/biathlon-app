import Foundation

/// Une course, issue de `Competitions?EventId=` ou du bloc `Competition` de `Results`.
public struct Competition: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let shortDescription: String
    public let description: String
    public let startTime: Date
    public let statusID: Int
    public let statusText: String?
    public let scheduleStatus: String?
    public let resultStatus: String?
    public let isLive: Bool
    public let hasLiveData: Bool
    public let disciplineID: String?
    public let categoryID: String?
    public let distanceKm: String?
    public let shootingCount: Int?
    public let legCount: Int?
    public let location: String?

    enum CodingKeys: String, CodingKey {
        case id = "RaceId"
        case shortDescription = "ShortDescription"
        case description = "Description"
        case startTime = "StartTime"
        case statusID = "StatusId"
        case statusText = "StatusText"
        case scheduleStatus = "ScheduleStatus"
        case resultStatus = "ResultStatus"
        case isLive = "IsLive"
        case hasLiveData = "HasLiveData"
        case disciplineID = "DisciplineId"
        case categoryID = "catId"
        case distanceKm = "km"
        case shootingCount = "NrShootings"
        case legCount = "NrLegs"
        case location = "Location"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortDescription = try c.decode(String.self, forKey: .shortDescription)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? shortDescription
        startTime = try c.decode(Date.self, forKey: .startTime)
        statusID = try c.decodeLooseInt(forKey: .statusID) ?? 0
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
        scheduleStatus = try c.decodeIfPresent(String.self, forKey: .scheduleStatus)
        resultStatus = try c.decodeIfPresent(String.self, forKey: .resultStatus)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        hasLiveData = try c.decodeIfPresent(Bool.self, forKey: .hasLiveData) ?? false
        disciplineID = try c.decodeIfPresent(String.self, forKey: .disciplineID)
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        distanceKm = try c.decodeLooseString(forKey: .distanceKm)
        shootingCount = try c.decodeLooseInt(forKey: .shootingCount)
        legCount = try c.decodeLooseInt(forKey: .legCount)
        location = try c.decodeIfPresent(String.self, forKey: .location)
    }

    public var state: State {
        if isLive { return .live }
        switch scheduleStatus?.uppercased() {
        case "FINISHED": return .finished
        case "CANCELLED", "CANCELED": return .cancelled
        case "POSTPONED", "DELAYED": return .delayed
        default: break
        }
        // Valeurs observées : 1 = Scheduled, 11 = Final. Les autres seront
        // cartographiées pendant les premières courses de la saison.
        return statusID == 11 ? .finished : .scheduled
    }

    public enum State: Sendable, Hashable {
        case scheduled, live, delayed, cancelled, finished
    }

    public var isRelay: Bool { (legCount ?? 0) > 1 }
}
