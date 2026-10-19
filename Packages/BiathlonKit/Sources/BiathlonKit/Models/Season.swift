import Foundation

/// IBU season ID, for example `2627` for the 2026-27 winter.
public struct SeasonID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// The season rolls over on July 1.
    public static func containing(_ date: Date, calendar: Calendar = .init(identifier: .gregorian)) -> SeasonID {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let start = month >= 7 ? year : year - 1
        return SeasonID(start: start)
    }

    public init(start: Int) {
        let a = start % 100
        let b = (start + 1) % 100
        rawValue = String(format: "%02d%02d", a, b)
    }

    public static var current: SeasonID { containing(.now) }

    public var previous: SeasonID {
        let start = 2000 + (Int(rawValue.prefix(2)) ?? 0)
        return SeasonID(start: start - 1)
    }

    /// `2026-27`
    public var displayName: String {
        "20\(rawValue.prefix(2))-\(rawValue.suffix(2))"
    }

    public var description: String { rawValue }
}

/// Competition level in the API (`Level=`).
public enum CompetitionLevel: Int, Sendable, CaseIterable {
    case worldCup = 1
    case ibuCup = 2
    case juniorCup = 3
}
