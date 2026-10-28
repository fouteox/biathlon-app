/// The athletes and nations a user follows, to pick out their result rows.
public struct FavoriteSet: Equatable, Sendable {
    public let athleteIDs: Set<String>
    public let nations: Set<String>

    public init(athleteIDs: Set<String>, nations: Set<String>) {
        self.athleteIDs = athleteIDs
        self.nations = nations
    }

    public var isEmpty: Bool { athleteIDs.isEmpty && nations.isEmpty }

    public func contains(_ row: ResultRow) -> Bool {
        if let id = row.athleteID, athleteIDs.contains(id) { return true }
        if let nation = row.nation, nations.contains(nation) { return true }
        return false
    }
}

extension RaceResults {
    /// A standings row is a favorite itself or, for a relay team, through one of its legs.
    public func isFavorite(_ row: ResultRow, in favorites: FavoriteSet) -> Bool {
        favorites.contains(row) || (row.isTeam && legs(of: row).contains(where: favorites.contains))
    }

    /// The first `count` standings, then the favorites ranked below them: each row once.
    public func featuredStandings(top count: Int, favorites: FavoriteSet) -> [ResultRow] {
        standings.prefix(count) + standings.dropFirst(count).filter { isFavorite($0, in: favorites) }
    }
}
