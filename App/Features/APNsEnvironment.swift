/// APNs environment matching the `aps-environment` entitlement Xcode signs the build
/// with. The server keeps device tokens and Live Activity channels per environment.
enum APNsEnvironment: String {
    case sandbox, production

    static var current: Self {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}
