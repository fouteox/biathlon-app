import BiathlonKit

extension APNsEnvironment {
    /// The environment matching the `aps-environment` entitlement Xcode signs the build with,
    /// as the configuration approximates it: the entitlement says `development`
    /// (Configs/Biathlon.entitlements), and Xcode signs `production` in its place only for
    /// distribution (TestFlight, the App Store). A Release build run from Xcode on a device
    /// therefore registers a sandbox token as production, which the server then sends to the
    /// wrong APNs host: run a Debug build from Xcode.
    static var current: Self {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}
