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
        Self.openTab("Standings", in: app)
        try assertRowsReadAsOneElement(in: app)
        assertFirstRowReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        // A menu picker reads its title and its value: "Discipline, Overall".
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discipline")).firstMatch.tap()
        app.buttons["Nations"].tap()
        // The star stays a button of its own beside the nation it adds.
        XCTAssertTrue(firstRow(in: app).buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
        assertFirstRowReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    /// The photo says nothing the name beside it doesn't: VoiceOver skips it.
    @MainActor func testAthleteScreenReadsTheProfileAndEachResultAsOneElement() throws {
        let app = launch()
        openFirstAthlete(in: app)
        let profile = firstRow(in: app)
        XCTAssertEqual(profile.images.count, 0)
        // The results load on their own, after the profile.
        let results = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Latest results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testCalendarAndEventRowsReadAsOneElement() throws {
        let app = launch()
        Self.openTab("Calendar", in: app)
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        firstRow(in: app).tap()
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testFavoriteRowsReadAsOneElement() throws {
        let app = launch()
        openFirstAthlete(in: app)
        let star = app.navigationBars.buttons["Add to favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: Self.timeout))
        star.tap()
        Self.teamButton(in: app, titled: "Add ").tap()
        // Leaves the favorites as they were for the next run, even when an assertion fails: the
        // store persists on the simulator.
        addTeardownBlock { @MainActor in
            Self.openTab("Standings", in: app)
            Self.teamButton(in: app, titled: "Remove ").tap()
            app.navigationBars.buttons["Remove from favorites"].tap()
        }

        Self.openTab("Favorites", in: app)
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testHomeRowsReadAsOneElement() throws {
        let app = launch()
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
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
        Self.openTab("Standings", in: app)
        let row = firstRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        row.tap()
        XCTAssertTrue(app.navigationBars.buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
    }

    /// The athlete's team, from the button below the profile.
    @MainActor private static func teamButton(in app: XCUIApplication, titled prefix: String) -> XCUIElement {
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

    /// VoiceOver reads each visible row in one go: a row holds a single element (a text, or the
    /// link it opens), beside its own buttons.
    @MainActor private func assertRowsReadAsOneElement(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout), file: file, line: line)
        for index in 0..<min(app.cells.count, 8) {
            let row = app.cells.element(boundBy: index)
            let parts = Self.readElements(of: try row.snapshot()).filter { $0.elementType != .button }
            XCTAssertLessThanOrEqual(
                parts.count, 1, "Row read in \(parts.count) parts: \(row.debugDescription)", file: file, line: line)
        }
    }

    /// The elements VoiceOver stops on: the outermost ones, since the tree also lists the texts
    /// that a grouped element reads together.
    @MainActor private static func readElements(of snapshot: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        snapshot.children.flatMap { child in
            child.elementType == .other && child.label.isEmpty ? readElements(of: child) : [child]
        }
    }

    /// Tab bar items are buttons, whatever the tab bar shows as on this iOS version.
    @MainActor private static func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: timeout))
        tab.tap()
    }
}
