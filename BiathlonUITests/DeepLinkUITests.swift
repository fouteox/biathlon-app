import XCTest

/// A link from the widget or the Live Activity opens the race itself.
final class DeepLinkUITests: XCTestCase {
    @MainActor func testARaceLinkOpensTheRace() throws {
        let app = XCUIApplication.launchInEnglish()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: XCUIApplication.dataTimeout))

        app.open(try Self.sprintLink())

        XCTAssertTrue(
            app.navigationBars.staticTexts["Men's Sprint"].waitForExistence(timeout: XCUIApplication.dataTimeout))
    }

    /// The settings sheet, left open, would hide the race: the link closes it.
    @MainActor func testARaceLinkClosesTheSettings() throws {
        let app = XCUIApplication.launchInEnglish()
        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: XCUIApplication.dataTimeout))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: XCUIApplication.dataTimeout))

        app.open(try Self.sprintLink())

        XCTAssertTrue(
            app.navigationBars.staticTexts["Men's Sprint"].waitForExistence(timeout: XCUIApplication.dataTimeout))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    /// The men's sprint of the sample's first event of the season, which runs from July.
    private static func sprintLink() throws -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let year = calendar.component(.year, from: .now)
        let start = calendar.component(.month, from: .now) >= 7 ? year : year - 1
        let season = "\(start % 100)\((start + 1) % 100)"
        return try XCTUnwrap(URL(string: "biathlon://race/BT\(season)SWRLCP01SMSP?name=Men%2010%20km%20Sprint"))
    }
}
