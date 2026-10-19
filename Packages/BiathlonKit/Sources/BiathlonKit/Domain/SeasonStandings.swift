import Foundation

/// World Cup standings, from the previous season until the current one has
/// its first race.
public struct SeasonStandings: Sendable {
    /// The season shown.
    public let season: SeasonID
    /// The season containing the request date.
    public let requestedSeason: SeasonID
    public let standings: CupStandings

    public var isFallback: Bool { season != requestedSeason }
}

extension IBUClient {
    public func worldCupStandings(
        category: RaceCategory, discipline: StandingsDiscipline, now: Date
    ) async throws -> SeasonStandings {
        let current = SeasonID.containing(now)
        let standings = try await cupStandings(
            cupID: Cup.worldCupID(current, category: category, discipline: discipline))
        guard standings.rows.isEmpty else {
            return SeasonStandings(season: current, requestedSeason: current, standings: standings)
        }
        let previous = current.previous
        return SeasonStandings(
            season: previous,
            requestedSeason: current,
            standings: try await cupStandings(
                cupID: Cup.worldCupID(previous, category: category, discipline: discipline)))
    }
}
