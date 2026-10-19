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

    init(kind: Kind, key: String, name: String, nation: String? = nil) {
        kindRaw = kind.rawValue
        self.key = key
        self.name = name
        self.nation = nation
        addedAt = .now
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .athlete }

    enum Kind: String, CaseIterable {
        case athlete, nation
    }
}

extension ModelContext {
    func isFavorite(_ kind: Favorite.Kind, key: String) -> Bool {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.kindRaw == raw && $0.key == key })
        return ((try? fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFavorite(_ kind: Favorite.Kind, key: String, name: String, nation: String? = nil) {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.kindRaw == raw && $0.key == key })
        if let existing = try? fetch(descriptor), !existing.isEmpty {
            existing.forEach { delete($0) }
        } else {
            insert(Favorite(kind: kind, key: key, name: name, nation: nation))
        }
    }
}
