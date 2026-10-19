import Foundation

extension JSONDecoder {
    /// Décodeur adapté à l'API IBU : les dates arrivent tantôt avec `Z`
    /// (`2026-11-26T15:15:00Z`), tantôt sans fuseau (`2001-06-29T00:00:00`).
    public static let ibu: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = IBUDateParser.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date IBU illisible : \(raw)"
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
    /// L'API renvoie certains nombres tantôt en chaîne, tantôt en nombre
    /// (rangs, points, distances). On les normalise en `String?`.
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
