import Observation

/// Whether the settings sheet is shown: opened from Home, or from the button iOS shows in
/// Settings > Notifications for the app.
@Observable
final class SettingsPresentation {
    var isPresented = false
}
