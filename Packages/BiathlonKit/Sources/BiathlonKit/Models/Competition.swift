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
    /// Whether the IBU publishes the race's analysis: its rankings of course, range and shooting times.
    public let hasAnalysis: Bool
    /// Shootings of each athlete, or of each leg of a relay.
    public let shootingCount: Int?

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
        case hasAnalysis = "HasAnalysis"
        case shootingCount = "NrShootings"
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
        hasAnalysis = try c.decodeIfPresent(Bool.self, forKey: .hasAnalysis) ?? false
        shootingCount = try c.decodeLooseInt(forKey: .shootingCount)
    }

    /// Same rules as the server (`server/src/ibu.ts`), checked against the
    /// shared `race-status.json` fixture. Observed values: StatusId 1
    /// "Scheduled", 6 "Cancelled", 11 "Final". biathlonresults.com shows
    /// results from StatusId 10, which covers results not yet official.
    public var state: State {
        if isLive { return .live }
        let text = "\(scheduleStatus ?? "") \(statusText ?? "")".uppercased()
        if text.contains("CANCEL") || statusID == 6 { return .cancelled }
        if text.contains("FINISHED") || statusID >= Self.firstResultStatusID { return .finished }
        return .scheduled
    }

    private static let firstResultStatusID = 10

    public enum State: String, CaseIterable, Codable, Sendable, Hashable {
        case scheduled, live, cancelled, finished
    }

    public var eventID: String { Self.eventID(ofRace: id) }

    /// A `RaceId` starts with its 14-character `EventId`, as biathlonresults.com reads it.
    public static func eventID(ofRace raceID: String) -> String { String(raceID.prefix(14)) }

    public var category: RaceCategory? { categoryID.flatMap(RaceCategory.init(rawValue:)) }

    public var kind: RaceKind? { RaceKind(raceID: id) }

    public var isRelay: Bool { (legCount ?? 0) > 1 }
}
