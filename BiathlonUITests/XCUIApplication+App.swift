import XCTest

extension XCUIApplication {
    /// The app loads its data asynchronously, on a CI machine that can be busy.
    nonisolated static let dataTimeout: TimeInterval = 30

    /// The app in English, whatever the simulator's language, so tests find elements by label. With
    /// `--sample-data` (`AppDelegate.asksForSampleData`), it runs on fictional data rather than the network,
    /// and starts with no favorites, whatever an earlier test added. `arguments` are passed on: a
    /// `-key value` pair seeds the app's `UserDefaults`, as the system reads such arguments.
    @MainActor static func launchInEnglish(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--sample-data"] + arguments
        app.launch()
        return app
    }

    /// Tab bar items are buttons, whatever the tab bar shows as on this iOS version.
    @MainActor func openTab(_ title: String) {
        let tab = buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: Self.dataTimeout))
        tab.tap()
    }

    /// A pop-up button of the toolbar, found by its identifier once it shows `value`.
    @MainActor func toolbarPicker(_ identifier: String, shows value: String) -> XCUIElement {
        navigationBars.buttons.matching(identifier: identifier)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
}
