// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FloatingTimers",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "FloatingTimers",
            targets: ["FloatingTimers"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "FloatingTimers",
            path: "Sources/FloatingTimers"
        ),
        .testTarget(
            name: "FloatingTimersTests",
            dependencies: ["FloatingTimers"],
            path: "Tests/FloatingTimersTests"
        ),
    ]
)
