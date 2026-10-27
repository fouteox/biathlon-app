import Foundation

/// World Cup standings of a season: by default the current one, or the previous
/// until the current one has its first race.
public struct SeasonStandings: Sendable {
    /// The season shown.
    public let season: SeasonID
    /// The season containing the request date.
    public let requestedSeason: SeasonID
    public let standings: CupStandings

    public var isFallback: Bool { season != requestedSeason }
}

extension IBUClient {
    /// The current season's standings, or the previous season's until the current one has its first race.
    public func worldCupStandings(
        category: RaceCategory, discipline: StandingsDiscipline, now: Date
    ) async throws -> SeasonStandings {
        let current = try await worldCupStandings(
            category: category, discipline: discipline, season: SeasonID.containing(now))
        guard current.standings.rows.isEmpty else { return current }
        let previous = try await worldCupStandings(
            category: category, discipline: discipline, season: current.season.previous)
        return SeasonStandings(season: previous.season, requestedSeason: current.season, standings: previous.standings)
    }

    /// The standings of `season`, as they are, even empty before its first race.
    public func worldCupStandings(
        category: RaceCategory, discipline: StandingsDiscipline, season: SeasonID
    ) async throws -> SeasonStandings {
        SeasonStandings(
            season: season,
            requestedSeason: season,
            standings: try await cupStandings(
                cupID: Cup.worldCupID(season, category: category, discipline: discipline)))
    }
}
