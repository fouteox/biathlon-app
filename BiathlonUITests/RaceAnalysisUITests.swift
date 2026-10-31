import XCTest

/// A finished race opens its analysis, whose pickers change the ranking shown.
final class RaceAnalysisUITests: XCTestCase {
    @MainActor func testMeasurePickerChangesTheRanking() {
        let app = XCUIApplication.launchInEnglish()
        let allResults = app.buttons["All results"]
        XCTAssertTrue(allResults.waitForExistence(timeout: XCUIApplication.dataTimeout))
        allResults.tap()

        // The last row of the results, which the analysis goes into once they are read.
        let analysis = app.buttons["Course, range and shooting times"]
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: XCUIApplication.dataTimeout))
        for _ in 0..<10 where !analysis.exists { list.swipeUp() }
        XCTAssertTrue(analysis.exists)
        analysis.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Analysis"].waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(app.toolbarPicker("measure", shows: "Course").exists)
        XCTAssertTrue(app.toolbarPicker("segment", shows: "Whole race").exists)
        // The list names the ranking too, so it reads on its own.
        XCTAssertTrue(app.staticTexts["Course · Whole race"].waitForExistence(timeout: XCUIApplication.dataTimeout))
        let leader = Self.firstRow(in: app)
        XCTAssertTrue(leader.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let courseLeader = leader.label

        app.navigationBars.buttons["measure"].tap()
        app.buttons["Shooting"].tap()
        XCTAssertTrue(app.toolbarPicker("measure", shows: "Shooting").waitForExistence(timeout: 5))
        // The sample data ranks each measure in another order.
        let changed = NSPredicate(format: "exists == true AND label != %@", courseLeader)
        expectation(for: changed, evaluatedWith: Self.firstRow(in: app))
        waitForExpectations(timeout: XCUIApplication.dataTimeout)

        app.navigationBars.buttons["segment"].tap()
        app.buttons["Shooting 2"].tap()
        XCTAssertTrue(app.toolbarPicker("segment", shows: "Shooting 2").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shooting · Shooting 2"].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// The first athlete of the ranking, a link to their profile.
    @MainActor private static func firstRow(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.firstMatch.buttons.firstMatch
    }
}
