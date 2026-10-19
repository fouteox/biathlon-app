/// IBU race category (`catId`).
public enum RaceCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case men = "SM"
    case women = "SW"
    case mixed = "MX"

    public var id: String { rawValue }
}
