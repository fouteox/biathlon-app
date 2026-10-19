// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BiathlonKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BiathlonKit", targets: ["BiathlonKit"]),
    ],
    targets: [
        .target(
            name: "BiathlonKit",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(
            name: "BiathlonKitTests",
            dependencies: ["BiathlonKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
