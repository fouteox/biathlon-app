import Foundation

/// An athlete's World Cup circuit results, season by season, as their profile shows them.
public struct AthleteHistory: Sendable {
    /// The World Cup, World Championships and Olympic races, which the rest of the app follows,
    /// newest first as `AllResults` lists them.
    public let results: [AthleteResult]
    /// The current season, then those with results, newest first.
    public let seasons: [SeasonID]
    /// The season the profile opens on: the newest with results, so that before the athlete's
    /// first race of the season it shows the last one, as the standings do.
    public let initialSeason: SeasonID

    public init(results: [AthleteResult], now: Date) {
        self.results = results.filter(\.isWorldCupCircuit)
        let current = SeasonID.containing(now)
        let withResults = Set(self.results.compactMap(\.seasonID))
        seasons = [current] + withResults.subtracting([current]).sorted(by: >)
        initialSeason = withResults.max() ?? current
    }

    public func results(in season: SeasonID) -> [AthleteResult] {
        results.filter { $0.seasonID == season }
    }
}

extension IBUClient {
    /// The athlete's row in the World Cup overall standings of `category` for `season`, or `nil`
    /// when they scored no points.
    public func worldCupStanding(
        of athleteID: String, category: RaceCategory, season: SeasonID
    ) async throws -> CupRow? {
        try await cupStandings(cupID: Cup.worldCupID(season, category: category, discipline: .total))
            .rows.first { $0.athleteID == athleteID }
    }
}
