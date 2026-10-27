import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Client for the biathlonresults.com API.
///
/// `baseURL` can also point to the server's read-only cache (`/ibu/`), which
/// exposes the same paths as the IBU API.
public struct IBUClient: Sendable {
    public static let ibuBaseURL = URL(string: "https://biathlonresults.com/modules/sportapi/api/")!

    public let baseURL: URL
    private let transport: HTTPTransport

    public init(baseURL: URL = IBUClient.ibuBaseURL, transport: @escaping HTTPTransport = URLSession.shared.transport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    // MARK: Calendar

    /// World Cup events (`Level=1`) of a season.
    public func events(season: SeasonID) async throws -> [BiathlonEvent] {
        try await get("Events", ["SeasonId": season.rawValue, "Level": "1"])
    }

    public func competitions(eventID: String) async throws -> [Competition] {
        try await get("Competitions", ["EventId": eventID])
    }

    /// The race `id`, among its event's: a race known by its ID alone, such as an athlete's result.
    public func race(id: String) async throws -> Competition {
        let races = try await competitions(eventID: Competition.eventID(ofRace: id))
        guard let race = races.first(where: { $0.id == id }) else { throw IBUError.unknownRace(id) }
        return race
    }

    /// Races of each event, requested together, in the order of `events`.
    func competitions(of events: [BiathlonEvent]) async throws -> [Competition] {
        try await withThrowingTaskGroup { group in
            for (index, event) in events.enumerated() {
                group.addTask { (index, try await competitions(eventID: event.id)) }
            }
            var races = [[Competition]](repeating: [], count: events.count)
            for try await (index, eventRaces) in group {
                races[index] = eventRaces
            }
            return races.flatMap(\.self)
        }
    }

    // MARK: Results

    public func results(raceID: String) async throws -> RaceResults {
        try await get("Results", ["RaceId": raceID])
    }

    /// Results of `race`, if any.
    func results(of race: Competition?) async throws -> RaceResults? {
        guard let race else { return nil }
        return try await results(raceID: race.id)
    }

    // MARK: Standings

    public func cupStandings(cupID: String) async throws -> CupStandings {
        try await get("CupResults", ["CupId": cupID])
    }

    // MARK: Athletes

    public func athlete(id: String) async throws -> AthleteBio {
        try await get("CISBios", ["IBUId": id])
    }

    public func athleteResults(id: String) async throws -> [AthleteResult] {
        struct Envelope: Decodable {
            let results: [AthleteResult]?
            enum CodingKeys: String, CodingKey { case results = "Results" }
        }
        let envelope: Envelope = try await get("AllResults", ["IBUId": id])
        return envelope.results ?? []
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var url = baseURL.appending(path: path)
        url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        let (data, response) = try await transport(URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw IBUError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw IBUError.http(http.statusCode) }
        do {
            return try JSONDecoder.ibu.decode(T.self, from: data)
        } catch {
            throw IBUError.decoding(path: path, underlying: error)
        }
    }
}

/// Failures of the IBU API. The app shows its own message for them and logs the details.
public enum IBUError: Error {
    case invalidResponse
    case http(Int)
    case decoding(path: String, underlying: any Error)
    /// The race isn't among its event's races.
    case unknownRace(String)
}
