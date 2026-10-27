import Foundation

/// IBU season ID, for example `2627` for the 2026-27 winter.
public struct SeasonID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// The season rolls over on July 1, in UTC like the server.
    public static func containing(_ date: Date) -> SeasonID {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
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

    /// The seasons from `first` to the one containing `now`, newest first.
    public static func since(_ first: SeasonID, now: Date) -> [SeasonID] {
        sequence(first: containing(now)) { $0.previous }.prefix { $0 >= first }
    }

    /// The oldest season of biathlonresults.com, whose `Seasons` start in 1957-58: its races are
    /// those of the 1958 World Championships in Saalfelden (`BT5758SWRLCH__`).
    public static let firstWithRaces = SeasonID(start: 1957)

    /// The first World Cup season, the oldest with standings (`CupResults?CupId=BT7778SWRLCP__SMTS`).
    public static let firstWorldCup = SeasonID(start: 1977)

    public var previous: SeasonID {
        SeasonID(start: start - 1)
    }

    /// The year the season starts: athletes' histories go back to the 1990s ("98/99").
    private var start: Int {
        let year = Int(rawValue.prefix(2)) ?? 0
        return year < 50 ? 2000 + year : 1900 + year
    }

    public static func < (lhs: SeasonID, rhs: SeasonID) -> Bool {
        lhs.start < rhs.start
    }

    /// `2026-27`
    public var displayName: String {
        "\(start)-\(rawValue.suffix(2))"
    }

    public var description: String { rawValue }
}
