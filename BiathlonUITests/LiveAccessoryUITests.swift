import XCTest

/// While a race is being run, it shows at the bottom of every tab and opens on a tap.
final class LiveAccessoryUITests: XCTestCase {
    @MainActor func testLiveRaceShowsOnEveryTabAndOpens() {
        // One of the sample's races being run (`--sample-live`, `AppDelegate.asksForLiveRace`).
        let app = XCUIApplication.launchInEnglish(arguments: ["--sample-live"])
        app.openTab("Calendar")
        let accessory = app.descendants(matching: .any).matching(identifier: "live-accessory").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertTrue(accessory.label.contains("Live"), accessory.label)

        accessory.tap()
        // The race sheet: the race's state as a badge, and a button to close it.
        XCTAssertTrue(app.staticTexts["Live"].firstMatch.waitForExistence(timeout: XCUIApplication.dataTimeout))
        let close = app.navigationBars.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: XCUIApplication.dataTimeout))
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2))
    }

    /// Without a live race, nothing takes the room above the tab bar.
    @MainActor func testNothingShowsWithoutALiveRace() {
        let app = XCUIApplication.launchInEnglish()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "live-accessory").firstMatch.exists)
    }
}
