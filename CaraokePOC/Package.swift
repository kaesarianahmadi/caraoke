// swift-tools-version: 5.8
// Caraoke PoC — original SwiftUI proof of concept for live lyrics on CarPlay.
// Zero third-party dependencies. The iOS UI/ActivityKit layer lives in iOS/
// (not part of this package target) and is validated with `swiftc -parse`;
// the platform-neutral timing core is compiled and unit-tested here.

import PackageDescription

let package = Package(
    name: "CaraokePOC",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CaraokeCore", targets: ["CaraokeCore"])
    ],
    targets: [
        .target(
            name: "CaraokeCore",
            path: "Sources/CaraokeCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CaraokeCoreTests",
            dependencies: ["CaraokeCore"],
            path: "Tests/CaraokeCoreTests"
        )
    ]
)
