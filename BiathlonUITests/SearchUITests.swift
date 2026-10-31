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
}
