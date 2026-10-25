import Observation
import Testing
import UserNotifications

@testable import Biathlon

struct AppDelegateTests {
    /// The button iOS shows in Settings > Notifications > Biathlon Live opens the app's settings.
    @Test(.timeLimit(.minutes(1))) func showsTheSettingsWhenTheSystemAsks() async {
        let delegate = AppDelegate()
        delegate.userNotificationCenter(.current(), openSettingsFor: nil)

        for await isPresented in Observations({ delegate.settingsPresentation.isPresented }) where isPresented {
            break
        }
        #expect(delegate.settingsPresentation.isPresented)
    }
}
