import Foundation

extension JSONDecoder {
    /// Decoder for the IBU API: dates come either with `Z`
    /// (`2026-11-26T15:15:00Z`) or with no time zone (`2001-06-29T00:00:00`).
    public static let ibu: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = IBUDateParser.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unreadable IBU date: \(raw)"
            )
        }
        return decoder
    }()
}

enum IBUDateParser {
    static func parse(_ raw: String) -> Date? {
        let withZone = raw.hasSuffix("Z") || raw.contains("+") ? raw : raw + "Z"
        if let date = try? Date(withZone, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? fractional.parse(withZone)
    }
}

extension KeyedDecodingContainer {
    /// The API returns some numbers either as strings or as numbers
    /// (ranks, points, distances). They are normalized to `String?`.
    func decodeLooseString(forKey key: Key) throws -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) { return string }
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return String(int) }
        if let double = try? decodeIfPresent(Double.self, forKey: key) { return String(double) }
        return nil
    }

    func decodeLooseInt(forKey key: Key) throws -> Int? {
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return int }
        if let string = try? decodeIfPresent(String.self, forKey: key) { return Int(string) }
        return nil
    }
}
