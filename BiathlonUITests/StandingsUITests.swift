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
        // The season it opens on depends on the date.
        XCTAssertTrue(
            list.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Men · Overall · '")).firstMatch.exists)

        app.buttons["Filters"].tap()
        app.buttons["Women"].tap()
        XCTAssertTrue(
            list.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Women · Overall · '")).firstMatch
                .waitForExistence(timeout: 5))

        app.buttons["Filters"].tap()
        app.buttons["Sprint"].tap()
        XCTAssertTrue(
            list.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Women · Sprint · '")).firstMatch
                .waitForExistence(timeout: 5))
    }

    /// A past season picked in the filters keeps the category and the discipline.
    @MainActor func testFiltersMenuPicksASeason() throws {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))

        app.buttons["Filters"].tap()
        app.buttons["Women"].tap()
        // The oldest season the menu offers, four before the current one, always has its standings.
        app.buttons["Filters"].tap()
        let season = try XCTUnwrap(
            app.buttons.matching(NSPredicate(format: "label MATCHES '[0-9]{4}-[0-9]{2}'")).allElementsBoundByIndex.last)
        let name = season.label
        season.tap()
        XCTAssertTrue(
            list.staticTexts["Women · Overall · \(name)"].waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
