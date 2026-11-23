// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "SessionKit",
    platforms: [.macOS("15.0")],
    products: [.library(name: "SessionKit", targets: ["SessionKit"])],
    dependencies: [
        .package(path: "../AppearanceKit"),
        .package(path: "../MatrixKit"),
    ],
    targets: [
        .target(
            name: "SessionKit",
            dependencies: ["AppearanceKit", "MatrixKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SessionKitTests", dependencies: ["SessionKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
