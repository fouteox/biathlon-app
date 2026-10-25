import BiathlonKit
import Foundation
import SwiftData
import Testing

@testable import Biathlon

struct FavoriteTests {
    private static func container() throws -> ModelContainer {
        try ModelContainer(for: Favorite.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func togglingAddsTheFavoriteThenRemovesIt() throws {
        let container = try Self.container()
        let context = container.mainContext

        context.toggleFavorite(.athlete, key: "BTFRA21003199601", name: "Julia Simon", nation: "FRA")
        let added = try context.fetch(FetchDescriptor<Favorite>())
        #expect(added.map(\.key) == ["BTFRA21003199601"])
        #expect(added.map(\.kind) == [.athlete])

        context.toggleFavorite(.athlete, key: "BTFRA21003199601", name: "Julia Simon", nation: "FRA")
        #expect(try context.fetch(FetchDescriptor<Favorite>()).isEmpty)
    }

    @Test func aNationAndAnAthleteWithTheSameKeyAreDistinct() throws {
        let container = try Self.container()
        let context = container.mainContext

        context.toggleFavorite(.nation, key: "FRA", name: "France")
        context.toggleFavorite(.athlete, key: "FRA", name: "Homonym")

        let kinds = try context.fetch(FetchDescriptor<Favorite>()).compactMap(\.kind)
        #expect(Set(kinds) == [.nation, .athlete])
    }

    /// A kind saved by a newer version isn't taken for an athlete.
    @Test func aFavoriteOfAnUnknownKindIsLeftOut() {
        let favorite = Favorite(kind: .athlete, key: "BTFRA21003199601", name: "Julia Simon")
        favorite.kindRaw = "team"

        #expect(favorite.kind == nil)
        let favorites = FavoriteSet([favorite])
        #expect(favorites.athleteIDs.isEmpty)
        #expect(favorites.nations.isEmpty)
    }

    /// Julia Simon's profile, as `CISBios` gives it.
    @Test func followsTheProfileGender() throws {
        let bio = try JSONDecoder().decode(
            AthleteBio.self,
            from: Data(#"{"IBUId":"BTFRA20910199601","FullName":"Julia SIMON","NAT":"FRA","GenderId":"W"}"#.utf8))
        let favorite = Favorite(kind: .athlete, key: bio.id, name: "Julia Simon")

        favorite.update(from: bio)

        #expect(favorite.gender == .woman)
        #expect(favorite.title == "Julia SIMON")
    }

    /// A team added from a profile is saved under its code, from the standings under the
    /// IBU's English name: both read in the app's language.
    @Test func aNationReadsInTheAppLanguage() {
        #expect(Favorite(kind: .nation, key: "FRA", name: "FRA").title == Nation.localizedName("FRA"))
        #expect(Favorite(kind: .nation, key: "NOR", name: "Norway").title == Nation.localizedName("NOR"))
    }
}
