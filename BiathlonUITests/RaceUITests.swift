import XCTest

/// A finished race opens on where and when it was held, then its results, and shares its podium.
final class RaceUITests: XCTestCase {
    /// Place and date are one row, read as one element, above the results.
    @MainActor func testRaceOpensOnItsPlaceAndDateInOneRow() {
        let app = XCUIApplication.launchInEnglish()
        let allResults = app.buttons["All results"]
        XCTAssertTrue(allResults.waitForExistence(timeout: XCUIApplication.dataTimeout))
        allResults.tap()

        // One element says where (one of the sample's places), when (a dated day) and that it is over.
        let heading = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label MATCHES %@", #".*(Nordvik|Lac-Blanc|Hohenwald).*\b20\d{2}\b.*Finished.*"#)
        ).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(app.staticTexts["Results"].exists)
    }

    @MainActor func testFinishedRaceOffersToShareItsPodium() {
        let app = XCUIApplication.launchInEnglish()
        let allResults = app.buttons["All results"]
        XCTAssertTrue(allResults.waitForExistence(timeout: XCUIApplication.dataTimeout))
        allResults.tap()

        // Its sentence is BiathlonTests' (RaceSummary); the sheet is the system's.
        XCTAssertTrue(app.buttons["share"].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
