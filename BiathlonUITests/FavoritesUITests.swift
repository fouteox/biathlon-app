import XCTest

/// The favorites tab says where each favorite stands, before the setting below the list.
final class FavoritesUITests: XCTestCase {
    @MainActor func testFavoritesShowTheirStandingAboveTheLiveActivitySetting() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let leader = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(leader.waitForExistence(timeout: XCUIApplication.dataTimeout))
        leader.tap()
        let star = app.navigationBars.buttons["Add to favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: XCUIApplication.dataTimeout))
        star.tap()

        app.openTab("Favorites")
        // The leader of the sample's standings, with their rank and points, read as one element.
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let standing = row.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1 · 1000 points")).firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: XCUIApplication.dataTimeout), row.buttons.firstMatch.label)
        XCTAssertTrue(app.staticTexts["Rank and points in the World Cup overall standings."].exists)

        // The Live Activity setting comes after the favorites.
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.exists)
        XCTAssertGreaterThan(toggle.frame.minY, row.frame.maxY)
    }
}
