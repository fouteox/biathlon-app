import BiathlonKit

extension APNsEnvironment {
    /// The environment matching the `aps-environment` entitlement Xcode signs the build with.
    static var current: Self {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}
