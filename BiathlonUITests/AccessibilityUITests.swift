import XCTest

/// How VoiceOver reads the app's lists. The app runs on `IBUClient.sample`'s fictional World Cup, laid
/// out around today's date: the tests look for the shape of each screen, never for a given name.
final class AccessibilityUITests: XCTestCase {
    /// What the audits leave to other changes: the layout at accessibility text sizes, and the
    /// contrast of the system colors, which only a device shows faithfully.
    private static let auditTypes = XCUIAccessibilityAuditType.all.subtracting([
        .dynamicType, .textClipped, .contrast,
    ])
    private static let timeout = XCUIApplication.dataTimeout

    @MainActor func testStandingsRowsReadAsOneElementWithTheirPoints() throws {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Standings")
        try assertRowsReadAsOneElement(in: app)
        assertFirstStandingReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        // The discipline is a pop-up button in the toolbar.
        let discipline = app.navigationBars.buttons["discipline"]
        discipline.tap()
        app.buttons["Nations"].tap()
        XCTAssertTrue(
            app.navigationBars.buttons.matching(identifier: "discipline")
                .matching(NSPredicate(format: "label CONTAINS %@", "Nations")).firstMatch
                .waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
        assertFirstStandingReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        // A nation opens on its athletes in the overall standings, with its star in the toolbar.
        firstStanding(in: app).tap()
        XCTAssertTrue(app.navigationBars.buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.collectionViews.staticTexts["Men · Overall"].waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
        assertFirstStandingReadsItsPoints(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    /// The photo says nothing the name beside it doesn't: VoiceOver skips it.
    @MainActor func testAthleteScreenReadsTheProfileAndEachResultAsOneElement() throws {
        let app = XCUIApplication.launchInEnglish()
        openFirstAthlete(in: app)
        // The results load on their own, after the profile; once they show, the list on screen is
        // the athlete's, not the standings left behind.
        let results = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: Self.timeout))
        // The first athlete of the standings has a rank in them, for the season the toolbar picks.
        let standing = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "World Cup standings"))
        XCTAssertTrue(standing.firstMatch.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(Self.seasonPicker(in: app).exists)
        // The profile reads its texts and nothing else: the photo, or the symbol shown in its
        // place, adds no words of its own.
        let profile = try XCTUnwrap(Self.readElements(of: try firstRow(in: app).snapshot()).first)
        let texts = profile.children.filter { $0.elementType == .staticText }.map(\.label)
        XCTAssertEqual(profile.label, texts.joined(separator: ", "))
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    /// An athlete's result opens its race, which the athlete finished.
    @MainActor func testAthleteResultOpensItsRace() {
        let app = XCUIApplication.launchInEnglish()
        openFirstAthlete(in: app)
        let results = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: Self.timeout))
        // The season's first race, at the end of the list.
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 { list.swipeUp() }
        list.cells.element(boundBy: list.cells.count - 1).tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.navigationBars.buttons["Add to favorites"].exists)
    }

    @MainActor func testCalendarAndEventRowsReadAsOneElement() throws {
        let app = XCUIApplication.launchInEnglish()
        app.openTab("Calendar")
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)

        // The last season is over: its events all have their schedule, whatever today's date.
        let season = Self.seasonPicker(in: app)
        let current = String(season.label.suffix(7))
        season.tap()
        app.buttons.matching(NSPredicate(format: "label == %@", Self.season(before: current))).firstMatch.tap()
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout))
        firstRow(in: app).tap()
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testFavoriteRowsReadAsOneElement() throws {
        let app = XCUIApplication.launchInEnglish()
        openFirstAthlete(in: app)
        let star = app.navigationBars.buttons["Add to favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: Self.timeout))
        star.tap()
        // Leaves the favorites as they were for the next run, even when a step below fails: the
        // store persists on the simulator.
        addTeardownBlock { @MainActor in
            app.openTab("Standings")
            for remove in [
                Self.teamButton(in: app, titled: "Remove "), app.navigationBars.buttons["Remove from favorites"],
            ] where remove.exists {
                remove.tap()
            }
        }
        // The athlete's team shows with the profile, which can load after the toolbar's star.
        let team = Self.teamButton(in: app, titled: "Add ")
        XCTAssertTrue(team.waitForExistence(timeout: Self.timeout))
        team.tap()

        app.openTab("Favorites")
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor func testHomeRowsReadAsOneElement() throws {
        let app = XCUIApplication.launchInEnglish()
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: Self.timeout))
        try assertRowsReadAsOneElement(in: app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    @MainActor private func firstRow(in app: XCUIApplication) -> XCUIElement {
        app.cells.firstMatch
    }

    /// The standings' first row: the list's header, which names the standings shown, comes before it
    /// as a cell of its own.
    @MainActor private func firstStanding(in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.button, identifier: nil).firstMatch
    }

    @MainActor private func openFirstAthlete(in app: XCUIApplication) {
        app.openTab("Standings")
        let row = firstStanding(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        row.tap()
        XCTAssertTrue(app.navigationBars.buttons["Add to favorites"].waitForExistence(timeout: Self.timeout))
    }

    /// The athlete's team, from the button below the profile.
    @MainActor private static func teamButton(in app: XCUIApplication, titled prefix: String) -> XCUIElement {
        app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The score reads with its unit, not as a bare number.
    @MainActor private func assertFirstStandingReadsItsPoints(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let row = firstStanding(in: app)
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

    /// The season picker in the toolbar, which reads the season shown, such as "2026-27".
    @MainActor private static func seasonPicker(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*20[0-9]{2}-[0-9]{2}")).firstMatch
    }

    /// "2025-26" for "2026-27".
    private static func season(before season: String) -> String {
        let start = Int(season.prefix(4)) ?? 0
        return "\(start - 1)-\(String(start).suffix(2))"
    }
}
