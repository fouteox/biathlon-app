import XCTest

/// The search finds an athlete by the start of a name and opens their profile.
final class SearchUITests: XCTestCase {
    @MainActor func testFindsAnAthleteAndOpensTheirProfile() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: XCUIApplication.dataTimeout))
        field.tap()
        // A fictional athlete of the sample data.
        field.typeText("mart")

        let athlete = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hugo MARTEL")).firstMatch
        XCTAssertTrue(athlete.waitForExistence(timeout: XCUIApplication.dataTimeout))
        athlete.tap()
        XCTAssertTrue(
            app.navigationBars.staticTexts["Hugo MARTEL"].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// Before anything is typed, the favorite athletes are suggested, and a suggestion opens its profile.
    @MainActor func testSuggestsTheFavoriteAthletesBeforeTyping() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let leader = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(leader.waitForExistence(timeout: XCUIApplication.dataTimeout))
        leader.tap()
        let star = app.navigationBars.buttons["Add to favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: XCUIApplication.dataTimeout))
        star.tap()
        let name = app.navigationBars.staticTexts.firstMatch.label

        app.openTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: XCUIApplication.dataTimeout))
        field.tap()
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: XCUIApplication.dataTimeout))
        suggestion.tap()
        XCTAssertTrue(app.navigationBars.staticTexts[name].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
