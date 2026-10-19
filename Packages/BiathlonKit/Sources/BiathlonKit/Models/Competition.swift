import Foundation

/// A race, from `Competitions?EventId=` or the `Competition` block of `Results`.
public struct Competition: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let shortDescription: String
    public let startTime: Date
    public let statusID: Int
    public let scheduleStatus: String?
    public let isLive: Bool
    public let categoryID: String?
    public let legCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "RaceId"
        case shortDescription = "ShortDescription"
        case startTime = "StartTime"
        case statusID = "StatusId"
        case scheduleStatus = "ScheduleStatus"
        case isLive = "IsLive"
        case categoryID = "catId"
        case legCount = "NrLegs"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortDescription = try c.decode(String.self, forKey: .shortDescription)
        startTime = try c.decode(Date.self, forKey: .startTime)
        statusID = try c.decodeLooseInt(forKey: .statusID) ?? 0
        scheduleStatus = try c.decodeIfPresent(String.self, forKey: .scheduleStatus)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        legCount = try c.decodeLooseInt(forKey: .legCount)
    }

    public var state: State {
        if isLive { return .live }
        switch scheduleStatus?.uppercased() {
        case "FINISHED": return .finished
        case "CANCELLED", "CANCELED": return .cancelled
        case "POSTPONED", "DELAYED": return .delayed
        default: break
        }
        // Observed values: 1 = Scheduled, 11 = Final. The others will be
        // mapped during the first races of the season.
        return statusID == 11 ? .finished : .scheduled
    }

    public enum State: Sendable, Hashable {
        case scheduled, live, delayed, cancelled, finished
    }

    public var isRelay: Bool { (legCount ?? 0) > 1 }
}
