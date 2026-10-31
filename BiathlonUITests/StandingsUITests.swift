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

    /// Each choice is a pop-up button in the toolbar, which shows the standings shown.
    @MainActor func testToolbarPickersChangeTheStandingsShown() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(app.toolbarPicker("category", shows: "Men").exists)
        XCTAssertTrue(app.toolbarPicker("discipline", shows: "Overall").exists)

        app.navigationBars.buttons["category"].tap()
        app.buttons["Women"].tap()
        XCTAssertTrue(app.toolbarPicker("category", shows: "Women").waitForExistence(timeout: 5))

        app.navigationBars.buttons["discipline"].tap()
        app.buttons["Sprint"].tap()
        XCTAssertTrue(app.toolbarPicker("discipline", shows: "Sprint").waitForExistence(timeout: 5))
        XCTAssertTrue(app.toolbarPicker("category", shows: "Women").exists)
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// A past season keeps the category. How far back the seasons go is `SeasonID.since`'s, which
    /// BiathlonKit tests: a menu shows only the seasons it has room for, and a swipe closes it.
    @MainActor func testSeasonPickerShowsAPastSeason() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        app.navigationBars.buttons["category"].tap()
        app.buttons["Women"].tap()

        app.navigationBars.buttons["season"].tap()
        // Two seasons before the current one: always over, with its standings.
        let past = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}")).element(
            boundBy: 2)
        let name = past.label
        past.tap()
        XCTAssertTrue(app.toolbarPicker("season", shows: name).waitForExistence(timeout: 5))
        XCTAssertTrue(app.toolbarPicker("category", shows: "Women").exists)
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }
}
