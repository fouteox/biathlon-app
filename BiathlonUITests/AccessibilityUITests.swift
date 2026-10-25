import XCTest

/// How VoiceOver reads the app's lists. The app runs on the data the server's cache serves at the
/// time, off season as well: the tests look for the shape of each screen, never for a given name.
final class AccessibilityUITests: XCTestCase {
    /// What the audits leave to other changes: the layout at accessibility text sizes, and the
    /// contrast of the system colors, which only a device shows faithfully.
    private static let auditTypes = XCUIAccessibilityAuditType.all.subtracting([
        .dynamicType, .textClipped, .contrast,
    ])
    /// Data comes from the network.
    private static let timeout: TimeInterval = 30

    @MainActor func testStandingsRowsReadAsOneElementWithTheirPoints() throws {
        let app = launch()
        app.tabBars.buttons["Standings"].tap()
        assertRowsReadAsOneElement(in: app)
        assertFirstRowReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        app.buttons["Discipline"].tap()
        app.buttons["Nations"].tap()
        // The star stays a button of its own beside the nation it adds.
        XCTAssertTrue(firstRow(in: app).buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
        assertRowsReadAsOneElement(in: app)
        assertFirstRowReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    /// The photo says nothing the name beside it doesn't: VoiceOver skips it.
    @MainActor func testAthleteScreenReadsTheProfileAndEachResultAsOneElement() throws {
        let app = launch()
        openFirstAthlete(in: app)
        let profile = firstRow(in: app)
        XCTAssertEqual(profile.images.count, 0)
        assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testCalendarAndEventRowsReadAsOneElement() throws {
        let app = launch()
        app.tabBars.buttons["Calendar"].tap()
        assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        firstRow(in: app).tap()
        assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testFavoriteRowsReadAsOneElement() throws {
        let app = launch()
        openFirstAthlete(in: app)
        let star = app.navigationBars.buttons["Add to favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: Self.timeout))
        star.tap()
        teamButton(in: app, titled: "Add ").tap()

        app.tabBars.buttons["Favorites"].tap()
        assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        // Leaves the favorites as they were for the next run.
        app.tabBars.buttons["Standings"].tap()
        teamButton(in: app, titled: "Remove ").tap()
        app.navigationBars.buttons["Remove from favorites"].tap()
    }

    @MainActor func testHomeRowsReadAsOneElement() throws {
        let app = launch()
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout))
        assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor private func firstRow(in app: XCUIApplication) -> XCUIElement {
        app.cells.firstMatch
    }

    @MainActor private func openFirstAthlete(in app: XCUIApplication) {
        app.tabBars.buttons["Standings"].tap()
        let row = firstRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        row.tap()
        XCTAssertTrue(app.navigationBars.buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
    }

    /// The athlete's team, from the button below the profile.
    @MainActor private func teamButton(in app: XCUIApplication, titled prefix: String) -> XCUIElement {
        app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The score reads with its unit, not as a bare number.
    @MainActor private func assertFirstRowReadsItsPoints(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let row = firstRow(in: app)
        let points = row.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", " points"))
        XCTAssertTrue(points.firstMatch.exists, row.debugDescription, file: file, line: line)
    }

    /// VoiceOver reads each visible row in one go: a row holds a single text or image element
    /// (none when the row is a link, which reads its label itself), beside its own buttons.
    @MainActor private func assertRowsReadAsOneElement(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout), file: file, line: line)
        for index in 0..<min(app.cells.count, 8) {
            let row = app.cells.element(boundBy: index)
            let parts = row.staticTexts.count + row.images.count
            XCTAssertLessThanOrEqual(
                parts, 1, "Row read in \(parts) parts: \(row.debugDescription)", file: file, line: line)
        }
    }
}
