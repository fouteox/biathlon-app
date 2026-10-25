import BiathlonKit
import Foundation
import SwiftData
import os

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
    /// From the IBU profile (`update(from:)`), for "Deceased" to agree in French.
    var genderRaw: String?

    init(kind: Kind, key: String, name: String, nation: String? = nil) {
        kindRaw = kind.rawValue
        self.key = key
        self.name = name
        self.nation = nation
        addedAt = .now
    }

    /// `nil` for a kind this version doesn't know, saved by a newer one before a downgrade:
    /// left out of the favorites rather than taken for another kind.
    var kind: Kind? {
        let kind = Kind(rawValue: kindRaw)
        if kind == nil { Logger.data.error("Unknown favorite kind \(self.kindRaw, privacy: .public)") }
        return kind
    }

    enum Kind: String {
        case athlete, nation
    }

    var gender: Gender? { genderRaw.flatMap(Gender.init(rawValue:)) }

    /// A nation reads in the app's language whatever name it was saved under.
    var title: String {
        kindRaw == Kind.nation.rawValue ? Nation.localizedName(key) : name
    }
}

extension ModelContext {
    func toggleFavorite(_ kind: Favorite.Kind, key: String, name: String, nation: String? = nil) {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.kindRaw == raw && $0.key == key })
        let existing: [Favorite]
        do {
            existing = try fetch(descriptor)
        } catch {
            // Inserting anyway could duplicate a favorite the fetch missed.
            Logger.data.error("Looking up a favorite failed: \(String(describing: error), privacy: .public)")
            return
        }
        if existing.isEmpty {
            insert(Favorite(kind: kind, key: key, name: name, nation: nation))
        } else {
            for favorite in existing { delete(favorite) }
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
        if genderRaw != bio.gender?.rawValue { genderRaw = bio.gender?.rawValue }
    }
}

extension FavoriteSet {
    init(_ favorites: [Favorite]) {
        self.init(
            athleteIDs: Set(favorites.filter { $0.kind == .athlete }.map(\.key)),
            nations: Set(favorites.filter { $0.kind == .nation }.map(\.key)))
    }
}
