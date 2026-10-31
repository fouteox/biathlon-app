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

    /// The anchor comes first under the event: the next race, larger, with how far away it is.
    @MainActor func testNextRaceIsTheAnchorUnderTheEvent() {
        let app = XCUIApplication.launchInEnglish()
        let event = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: XCUIApplication.dataTimeout))
        // On the sample data no race is live, so the next race is the first dated row, and it isn't over.
        let anchor = app.cells.containing(.button, identifier: nil)
            .matching(NSPredicate(format: "label MATCHES %@", ".*\\b(19|20)[0-9]{2}\\b.*")).firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertFalse(anchor.label.contains("Finished"), anchor.label)
    }

    /// The latest result names its race in its header and says when it started in its footer, under the podium.
    @MainActor func testLatestResultSaysWhichRaceAndWhenItStarted() {
        let app = XCUIApplication.launchInEnglish()
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Latest result ·")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: XCUIApplication.dataTimeout))
        // The footer: the start date with the year and, between two events, the place.
        let footer = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\b(19|20)[0-9]{2}\\b.*"))
        XCTAssertTrue(footer.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
