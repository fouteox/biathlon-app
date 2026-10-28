import XCTest

extension XCUIApplication {
    /// The app loads its data asynchronously, on a CI machine that can be busy.
    nonisolated static let dataTimeout: TimeInterval = 30

    /// The app in English, whatever the simulator's language, so tests find elements by label. It runs
    /// on fictional data (`--sample-data`, read by `AppDelegate.clients(arguments:)`), not on the network.
    @MainActor static func launchInEnglish() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--sample-data"]
        app.launch()
        return app
    }

    /// Tab bar items are buttons, whatever the tab bar shows as on this iOS version.
    @MainActor func openTab(_ title: String) {
        let tab = buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: Self.dataTimeout))
        tab.tap()
    }
}
