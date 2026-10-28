import XCTest

/// The home screen reads from the event down to its races.
final class HomeUITests: XCTestCase {
    /// The event comes first, above the races it holds, and opens on its schedule.
    @MainActor func testEventComesFirstAndOpensItsRaces() {
        let app = XCUIApplication.launchInEnglish()
        // Section headers can show as cells of their own: the first row is the first cell with a link.
        let event = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: XCUIApplication.dataTimeout))
        // The flag, then the place: the event's title once opened.
        let place = event.staticTexts.element(boundBy: 1).label

        event.tap()
        XCTAssertTrue(
            app.navigationBars.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", place)).firstMatch
                .waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
