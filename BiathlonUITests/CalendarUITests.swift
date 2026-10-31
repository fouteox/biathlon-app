import XCTest

/// The calendar reads by month, and an event's schedule by day.
final class CalendarUITests: XCTestCase {
    private static let timeout = XCUIApplication.dataTimeout
    private static let year = ".*\\b(19|20)[0-9]{2}\\b.*"
    private static let weekday = "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\\b.*"

    /// Each month heads its events, and an event's days head its races, which keep the time alone.
    @MainActor func testMonthsHeadEventsAndDaysHeadRaces() {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Calendar")
        // A month header: its name and the year, a text of its own above the first event.
        let month = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", Self.year)).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: Self.timeout))

        // The first event's row, under it.
        let event = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: Self.timeout))
        event.tap()

        // A day header, then a race whose row (its link, which carries the label) says the time,
        // not the date again.
        let day = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", Self.weekday)).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(day.label.range(of: Self.year, options: .regularExpression) != nil, day.label)
        let race = app.cells.containing(.button, identifier: nil).firstMatch
        XCTAssertTrue(race.waitForExistence(timeout: Self.timeout))
        let label = race.buttons.firstMatch.label
        XCTAssertTrue(label.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil, label)
        XCTAssertNil(label.range(of: Self.year, options: .regularExpression), label)
    }
}
