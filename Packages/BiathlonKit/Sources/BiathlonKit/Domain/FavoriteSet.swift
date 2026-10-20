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
