import XCTest

/// The standings read like the other tabs: the same title, with their filters in a toolbar menu.
final class StandingsUITests: XCTestCase {
    /// A large title under a pinned filters bar showed blurred at the top of the list and flickered on
    /// the way back up; an inline title fixed that but no longer matched the other tabs.
    @MainActor func testTitleMatchesTheOtherTabsAndSettlesBackAtTheTop() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Calendar")
        let calendarTitle = app.navigationBars.staticTexts["Calendar"]
        XCTAssertTrue(calendarTitle.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let calendarTitleHeight = calendarTitle.frame.height

        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let title = app.navigationBars.staticTexts["Standings"]
        let atRest = title.frame
        XCTAssertEqual(atRest.height, calendarTitleHeight, "Same size as the Calendar title")

        list.swipeUp()
        list.swipeDown()
        list.swipeDown()
        XCTAssertEqual(title.frame, atRest, "Back at the top")
    }

    /// The filters sit in a toolbar menu and the list's header says which standings are shown.
    @MainActor func testFiltersMenuChangesTheStandingsNamedInTheListHeader() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(list.staticTexts["Men · Overall"].exists)

        app.buttons["Filters"].tap()
        app.buttons["Women"].tap()
        XCTAssertTrue(list.staticTexts["Women · Overall"].waitForExistence(timeout: 5))

        app.buttons["Filters"].tap()
        app.buttons["Sprint"].tap()
        XCTAssertTrue(list.staticTexts["Women · Sprint"].waitForExistence(timeout: 5))
    }
}
