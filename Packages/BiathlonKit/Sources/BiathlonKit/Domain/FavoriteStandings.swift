import Foundation

/// The overall standings of the season, athletes' and nations', men's and women's: where each
/// favorite stands, for the list of favorites.
public struct FavoriteStandings: Sendable {
    /// The season the standings are from: the previous one until the current has its first race.
    public let season: SeasonID
    let athletes: [RaceCategory: CupStandings]
    let nations: [RaceCategory: CupStandings]

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
    /// The four standings at once; the season is the athletes' standings', men's first.
    public func favoriteStandings(now: Date) async throws -> FavoriteStandings {
        async let men = worldCupStandings(category: .men, discipline: .total, now: now)
        async let women = worldCupStandings(category: .women, discipline: .total, now: now)
        async let menNations = worldCupStandings(category: .men, discipline: .nations, now: now)
        async let womenNations = worldCupStandings(category: .women, discipline: .nations, now: now)
        return FavoriteStandings(
            season: try await men.season,
            athletes: [.men: try await men.standings, .women: try await women.standings],
            nations: [.men: try await menNations.standings, .women: try await womenNations.standings])
    }
}
