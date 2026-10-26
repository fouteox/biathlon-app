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

        list.swipeUp()
        XCTAssertEqual(bars.map(\.frame), atRest, "Scrolled down")
        list.swipeDown()
        list.swipeDown()
        XCTAssertEqual(bars.map(\.frame), atRest, "Back at the top")
    }

    @MainActor func testDIAGScrollBackUpSlowly() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let bars = [app.navigationBars.firstMatch, app.segmentedControls.firstMatch]
        print("DIAG rest", Date.now, bars.map(\.frame), app.navigationBars.firstMatch.staticTexts.firstMatch.frame)
        for _ in 0..<3 { list.swipeUp() }
        print("DIAG down", Date.now, bars.map(\.frame), app.navigationBars.firstMatch.staticTexts.firstMatch.frame)
        for step in 0..<14 {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            print(
                "DIAG step", step, Date.now, bars.map(\.frame),
                app.navigationBars.firstMatch.staticTexts.firstMatch.frame)
        }
    }
}
