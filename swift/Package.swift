// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MisarReach",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "MisarReach",
            targets: ["MisarReach"]
        ),
    ],
    targets: [
        .target(
            name: "MisarReach",
            path: "Sources/MisarReach"
        ),
        .testTarget(
            name: "MisarReachTests",
            dependencies: ["MisarReach"],
            path: "Tests/MisarReachTests"
        ),
    ]
)
