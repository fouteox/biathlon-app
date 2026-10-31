import XCTest

/// A finished race shares its podium.
final class RaceUITests: XCTestCase {
    @MainActor func testFinishedRaceOffersToShareItsPodium() {
        let app = XCUIApplication.launchInEnglish()
        let allResults = app.buttons["All results"]
        XCTAssertTrue(allResults.waitForExistence(timeout: XCUIApplication.dataTimeout))
        allResults.tap()

        // Its sentence is BiathlonTests' (RaceSummary); the sheet is the system's.
        XCTAssertTrue(app.navigationBars.buttons["Share"].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
