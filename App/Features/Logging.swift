import Foundation
import os

/// `Logger` is `Sendable`: the loggers are usable from any isolation, like a SwiftData model's.
extension Logger {
    private nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? "com.fouteox.biathlon"

    /// Loading IBU data for the screens.
    nonisolated static let data = Logger(subsystem: subsystem, category: "data")
    /// APNs registration, the notification server and local reminders.
    nonisolated static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
