import Foundation
import Testing

struct LaunchScreenTests {
    /// HIG Launching: the launch screen should be nearly identical to the first screen, which
    /// sits in a navigation stack inside a tab view.
    @Test func showsTheBarsOfTheFirstScreen() throws {
        let launchScreen = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        #expect(launchScreen["UINavigationBar"] is [String: Any])
        #expect(launchScreen["UITabBar"] is [String: Any])
    }
}
