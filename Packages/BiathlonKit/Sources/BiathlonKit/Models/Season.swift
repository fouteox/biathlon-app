import Foundation

/// IBU season ID, for example `2627` for the 2026-27 winter.
public struct SeasonID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
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

    /// The season containing `now` and the `count - 1` before it, newest first.
    public static func recent(_ count: Int, now: Date) -> [SeasonID] {
        Array(sequence(first: containing(now)) { $0.previous }.prefix(count))
    }

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
