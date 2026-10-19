import Foundation

/// An event (Kontiolahti, Hochfilzen…), from `Events`.
public struct BiathlonEvent: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let shortDescription: String
    public let startDate: Date
    public let endDate: Date
    public let nation: String?

    enum CodingKeys: String, CodingKey {
        case id = "EventId"
        case shortDescription = "ShortDescription"
        case startDate = "StartDate"
        case endDate = "EndDate"
        case nation = "Nat"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortDescription = try c.decode(String.self, forKey: .shortDescription)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        nation = try c.decodeIfPresent(String.self, forKey: .nation)
    }

    /// World Championships IDs end in `SWRLCH__` (`BT2425SWRLCH__`), World Cup
    /// stages in `SWRLCP` and a number.
    public var isWorldChampionships: Bool { id.hasSuffix("SWRLCH__") }
}
