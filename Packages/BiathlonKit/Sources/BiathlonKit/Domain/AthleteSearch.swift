import Foundation

/// A person found by the IBU's `Athletes?FamilyName=&GivenName=` search, which matches the start of
/// the family name and of the given name, whatever their case, and returns at most 10 people.
public struct AthleteMatch: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let familyName: String
    public let givenName: String
    public let nation: String?
    /// "Athlete", "Not active" for a former athlete, "Official", or several ("Athlete, Official").
    let functions: String?

    enum CodingKeys: String, CodingKey {
        case id = "IBUId"
        case familyName = "FamilyName"
        case givenName = "GivenName"
        case nation = "NAT"
        case functions = "Functions"
    }

    /// As the athlete's profile names them: `Julia SIMON`.
    public var name: String { "\(givenName) \(familyName)" }

    /// The search also finds the IBU's officials, who have no results.
    var isAthlete: Bool { functions?.contains("Athlete") == true || functions == "Not active" }
}

/// What the app sends to the IBU's search for the text someone types.
public enum AthleteSearch {
    struct Query: Equatable, Sendable {
        var familyName: String?
        var givenName: String?

        var parameters: [String: String] {
            [("FamilyName", familyName), ("GivenName", givenName)].reduce(into: [:]) { parameters, item in
                if let value = item.1 { parameters[item.0] = value }
            }
        }
    }

    /// One word may start either name. Several may be a family name of several words
    /// (`fillon maillet`), or given names and a family name, each of one word or more, in either
    /// order (`quentin fillon maillet`, `simon julia`): every split is searched. Lowercased, so the
    /// server's cache serves every spelling.
    static func queries(for text: String) -> [Query] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return [] }
        guard words.count > 1 else { return [Query(familyName: first), Query(givenName: first)] }
        let splits = (1..<words.count).flatMap { index in
            let (start, end) = (words[..<index].joined(separator: " "), words[index...].joined(separator: " "))
            return [Query(familyName: end, givenName: start), Query(familyName: start, givenName: end)]
        }
        return [Query(familyName: words.joined(separator: " "))] + splits
    }

    /// The athletes of every answer, in the order of the queries and of the IBU's answers, once each.
    static func merge(_ answers: [[AthleteMatch]]) -> [AthleteMatch] {
        var seen = Set<String>()
        return answers.joined().filter { $0.isAthlete && seen.insert($0.id).inserted }
    }
}

extension IBUClient {
    /// The athletes, active or former, whose names start like the words of `text`.
    public func searchAthletes(_ text: String) async throws -> [AthleteMatch] {
        let queries = AthleteSearch.queries(for: text)
        let answers = try await withThrowingTaskGroup(of: (Int, [AthleteMatch]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask { (index, try await athletes(matching: query)) }
            }
            var answers = [[AthleteMatch]](repeating: [], count: queries.count)
            for try await (index, matches) in group { answers[index] = matches }
            return answers
        }
        return AthleteSearch.merge(answers)
    }

    private func athletes(matching query: AthleteSearch.Query) async throws -> [AthleteMatch] {
        struct Response: Decodable {
            let athletes: [AthleteMatch]
            enum CodingKeys: String, CodingKey { case athletes = "Athletes" }
        }
        let response: Response = try await get("Athletes", query.parameters)
        return response.athletes
    }
}
