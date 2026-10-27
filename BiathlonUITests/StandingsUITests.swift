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
        XCTAssertTrue(Self.picker("category", in: app, shows: "Men").exists)
        XCTAssertTrue(Self.picker("discipline", in: app, shows: "Overall").exists)

        app.navigationBars.buttons["category"].tap()
        app.buttons["Women"].tap()
        XCTAssertTrue(Self.picker("category", in: app, shows: "Women").waitForExistence(timeout: 5))

        app.navigationBars.buttons["discipline"].tap()
        app.buttons["Sprint"].tap()
        XCTAssertTrue(Self.picker("discipline", in: app, shows: "Sprint").waitForExistence(timeout: 5))
        XCTAssertTrue(Self.picker("category", in: app, shows: "Women").exists)
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// The seasons go back to the first World Cup, 1977-78, whose men's standings the IBU holds
    /// (`CupResults?CupId=BT7778SWRLCP__SMTS`).
    @MainActor func testSeasonPickerGoesBackToTheFirstWorldCup() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))

        app.navigationBars.buttons["season"].tap()
        // The menu only holds the seasons it shows: it scrolls down to the oldest.
        let seasons = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}"))
        let oldest = seasons["1977-78"]
        for _ in 0..<20 where !oldest.exists {
            // The menu also lists, off screen, a few seasons past those it shows.
            seasons.allElementsBoundByIndex.last(where: \.isHittable)?.swipeUp()
        }
        oldest.tap()
        XCTAssertTrue(Self.picker("season", in: app, shows: "1977-78").waitForExistence(timeout: 5))
        XCTAssertTrue(Self.picker("category", in: app, shows: "Men").exists)
        XCTAssertTrue(list.cells.firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// The toolbar's pop-up button `identifier` once it shows `value`.
    @MainActor private static func picker(_ identifier: String, in app: XCUIApplication, shows value: String)
        -> XCUIElement
    {
        app.navigationBars.buttons.matching(identifier: identifier)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
}
