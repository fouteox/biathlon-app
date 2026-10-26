import XCTest

/// The standings keep their filters pinned under the title while the list scrolls.
final class StandingsUITests: XCTestCase {
    /// A top bar whose height followed the scroll would move the safe area the list scrolls in, and
    /// the list would move the bar again: near the top, the title and the filters would flicker.
    @MainActor func testTitleAndFiltersStayPutWhileTheListScrolls() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let bars = [app.navigationBars.firstMatch, app.segmentedControls.firstMatch]
        let atRest = bars.map(\.frame)
        print("DIAG at rest", app.debugDescription)

        list.swipeUp()
        print("DIAG scrolled", app.debugDescription)
        XCTAssertEqual(bars.map(\.frame), atRest, "Scrolled down")
        list.swipeDown()
        list.swipeDown()
        XCTAssertEqual(bars.map(\.frame), atRest, "Back at the top")
    }
}
