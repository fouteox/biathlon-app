import BiathlonKit
import Foundation
import SwiftData

/// A favorite: an athlete (key = IBUId) or a nation (key = IOC code).
@Model
final class Favorite {
    #Unique<Favorite>([\.kindRaw, \.key])

    var kindRaw: String
    var key: String
    var name: String
    var nation: String?
    var addedAt: Date
    /// From the IBU profile (`update(from:)`).
    var isDeceased = false

    init(kind: Kind, key: String, name: String, nation: String? = nil) {
        kindRaw = kind.rawValue
        self.key = key
        self.name = name
        self.nation = nation
        addedAt = .now
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .athlete }

    enum Kind: String {
        case athlete, nation
    }
}

extension ModelContext {
    func toggleFavorite(_ kind: Favorite.Kind, key: String, name: String, nation: String? = nil) {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.kindRaw == raw && $0.key == key })
        if let existing = try? fetch(descriptor), !existing.isEmpty {
            for favorite in existing { delete(favorite) }
        } else {
            insert(Favorite(kind: kind, key: key, name: name, nation: nation))
        }
    }
}

extension Favorite {
    /// Follows the athlete's IBU profile, what was saved with the favorite going stale: an
    /// athlete can change nation (Jakov Fak, from CRO to SLO) or name, or pass away.
    func update(from bio: AthleteBio) {
        if name != bio.fullName { name = bio.fullName }
        if nation != bio.nation { nation = bio.nation }
        if isDeceased != bio.isDeceased { isDeceased = bio.isDeceased }
    }
}

extension FavoriteSet {
    init(_ favorites: [Favorite]) {
        self.init(
            athleteIDs: Set(favorites.filter { $0.kind == .athlete }.map(\.key)),
            nations: Set(favorites.filter { $0.kind == .nation }.map(\.key)))
    }
}
