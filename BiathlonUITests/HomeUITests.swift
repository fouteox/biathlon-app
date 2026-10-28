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

    /// The latest result says which race it was and when, above its podium.
    @MainActor func testLatestResultSaysWhenItsRaceStarted() {
        let app = XCUIApplication.launchInEnglish()
        // The race reads as one element: its name, its start date with the year, and its state.
        let race = app.cells.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label MATCHES %@", "Finished", ".*\\b(19|20)[0-9]{2}\\b.*"))
        XCTAssertTrue(race.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
