import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fouteox.biathlon"

    /// Loading IBU data for the screens.
    static let data = Logger(subsystem: subsystem, category: "data")
    /// APNs registration, the notification server and local reminders.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
