import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the biathlonresults.com API.
///
/// `baseURL` will point to our Cloudflare server (acting as a cache) once it
/// exists; it exposes the same paths as the IBU API.
public struct IBUClient: Sendable {
    public static let ibuBaseURL = URL(string: "https://biathlonresults.com/modules/sportapi/api/")!

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = IBUClient.ibuBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Calendar

    public func events(season: SeasonID, level: CompetitionLevel = .worldCup) async throws -> [BiathlonEvent] {
        try await get("Events", ["SeasonId": season.rawValue, "Level": String(level.rawValue)])
    }

    public func competitions(eventID: String) async throws -> [Competition] {
        try await get("Competitions", ["EventId": eventID])
    }

    // MARK: Results

    public func results(raceID: String) async throws -> RaceResults {
        try await get("Results", ["RaceId": raceID])
    }

    // MARK: Standings

    public func cups(season: SeasonID) async throws -> [Cup] {
        try await get("Cups", ["SeasonId": season.rawValue])
    }

    public func cupStandings(cupID: String) async throws -> CupStandings {
        try await get("CupResults", ["CupId": cupID])
    }

    // MARK: Athletes

    public func athlete(id: String) async throws -> AthleteBio {
        try await get("CISBios", ["IBUId": id])
    }

    public func athleteResults(id: String) async throws -> [AthleteResult] {
        struct Envelope: Decodable { let Results: [AthleteResult]? }
        let envelope: Envelope = try await get("AllResults", ["IBUId": id])
        return envelope.Results ?? []
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var url = baseURL.appending(path: path)
        url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw IBUError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw IBUError.http(http.statusCode) }
        do {
            return try JSONDecoder.ibu.decode(T.self, from: data)
        } catch {
            throw IBUError.decoding(path: path, underlying: error)
        }
    }
}

public enum IBUError: Error, LocalizedError {
    case invalidResponse
    case http(Int)
    case decoding(path: String, underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response."
        case .http(let code): "The server responded with \(code)."
        case .decoding(let path, _): "Unexpected data (\(path))."
        }
    }
}
