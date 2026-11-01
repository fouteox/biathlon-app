import Foundation

/// The overall standings of the season, athletes' and nations', men's and women's: where each
/// favorite stands, for the list of favorites.
public struct FavoriteStandings: Sendable {
    /// The season the standings are from: the previous one until the current has its first race.
    public let season: SeasonID
    /// The season containing the request date.
    public let requestedSeason: SeasonID
    let athletes: [RaceCategory: CupStandings]
    let nations: [RaceCategory: CupStandings]

    /// The previous season's standings, shown until the current season has its first race.
    public var isFallback: Bool { season != requestedSeason }

    /// Before the season's first race, any of the four can still be empty.
    var isEmpty: Bool {
        athletes.values.contains { $0.rows.isEmpty } || nations.values.contains { $0.rows.isEmpty }
    }

    /// The athlete's row, in whichever category they race.
    public func standing(ofAthlete id: String) -> CupRow? {
        RaceCategory.withStandings.lazy.compactMap { athletes[$0]?.rows.first { $0.athleteID == id } }.first
    }

    /// The nation's rows, men's then women's, in the Nations Cup, which keys them by code.
    public func standings(ofNation code: String) -> [(category: RaceCategory, row: CupRow)] {
        RaceCategory.withStandings.compactMap { category in
            nations[category]?.rows.first { $0.nation == code || $0.athleteID == code }.map { (category, $0) }
        }
    }
}

extension RaceCategory {
    /// Standings exist for men and women only.
    public static let withStandings: [RaceCategory] = [.men, .women]
}

extension IBUClient {
    /// The four standings at once, all of one season: the current one, or the previous one while any
    /// of the four is still empty, so the favorites never mix two seasons around the opening races.
    public func favoriteStandings(now: Date) async throws -> FavoriteStandings {
        let requested = SeasonID.containing(now)
        let current = try await favoriteStandings(season: requested, requested: requested)
        guard current.isEmpty else { return current }
        return try await favoriteStandings(season: requested.previous, requested: requested)
    }

    private func favoriteStandings(season: SeasonID, requested: SeasonID) async throws -> FavoriteStandings {
        async let men = cupStandings(cupID: Cup.worldCupID(season, category: .men, discipline: .total))
        async let women = cupStandings(cupID: Cup.worldCupID(season, category: .women, discipline: .total))
        async let menNations = cupStandings(cupID: Cup.worldCupID(season, category: .men, discipline: .nations))
        async let womenNations = cupStandings(cupID: Cup.worldCupID(season, category: .women, discipline: .nations))
        return FavoriteStandings(
            season: season,
            requestedSeason: requested,
            athletes: [.men: try await men, .women: try await women],
            nations: [.men: try await menNations, .women: try await womenNations])
    }
}
