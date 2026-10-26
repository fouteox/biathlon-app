import XCTest

extension XCUIApplication {
    /// Data comes from the network.
    static let dataTimeout: TimeInterval = 30

    /// The app in English, whatever the simulator's language, so tests find elements by label.
    @MainActor static func launchInEnglish() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
