import XCTest

/// The standings keep their filters pinned under the title while the list scrolls.
final class StandingsUITests: XCTestCase {
    /// A title or a bar that changed with the scroll flickered near the top: a large title under the
    /// filters' edge effect, or a bar whose height moved the list it sits above.
    @MainActor func testTitleAndFiltersStayPutWhileTheListScrolls() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let bars = [
            app.navigationBars.firstMatch, app.navigationBars.staticTexts["Standings"],
            app.segmentedControls.firstMatch,
        ]
        let atRest = bars.map(\.frame)

        list.swipeUp()
        XCTAssertEqual(bars.map(\.frame), atRest, "Scrolled down")
        list.swipeDown()
        list.swipeDown()
        XCTAssertEqual(bars.map(\.frame), atRest, "Back at the top")
    }
}
