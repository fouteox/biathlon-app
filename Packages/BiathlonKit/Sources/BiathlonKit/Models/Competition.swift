import Foundation

/// A race, from `Competitions?EventId=` or the `Competition` block of `Results`.
public struct Competition: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let shortDescription: String
    public let startTime: Date
    public let statusID: Int
    public let statusText: String?
    public let scheduleStatus: String?
    public let isLive: Bool
    public let categoryID: String?
    public let legCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "RaceId"
        case shortDescription = "ShortDescription"
        case startTime = "StartTime"
        case statusID = "StatusId"
        case statusText = "StatusText"
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
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
        scheduleStatus = try c.decodeIfPresent(String.self, forKey: .scheduleStatus)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        legCount = try c.decodeLooseInt(forKey: .legCount)
    }

    /// Same rules as the server (`server/src/ibu.ts`), checked against the
    /// shared `race-status.json` fixture. Observed values: StatusId 1
    /// "Scheduled", 6 "Cancelled", 11 "Final".
    public var state: State {
        if isLive { return .live }
        let text = "\(scheduleStatus ?? "") \(statusText ?? "")".uppercased()
        if text.contains("CANCEL") || statusID == 6 { return .cancelled }
        if text.contains("FINISHED") || statusID == 11 { return .finished }
        return .scheduled
    }

    public enum State: String, Sendable, Hashable {
        case scheduled, live, cancelled, finished
    }

    public var category: RaceCategory? { categoryID.flatMap(RaceCategory.init(rawValue:)) }

    public var isRelay: Bool { (legCount ?? 0) > 1 }
}
