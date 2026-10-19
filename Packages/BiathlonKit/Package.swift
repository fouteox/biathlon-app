// swift-tools-version: 6.2
import PackageDescription

/// Same concurrency semantics as the app target (Xcode's "Approachable
/// Concurrency" setting). Default isolation stays nonisolated, as for any library.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "BiathlonKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BiathlonKit", targets: ["BiathlonKit"])
    ],
    targets: [
        .target(
            name: "BiathlonKit",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BiathlonKitTests",
            dependencies: ["BiathlonKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)
