// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "MeterKit",
    platforms: [.macOS("15.0")],
    products: [.library(name: "MeterKit", targets: ["MeterKit"])],
    targets: [
        .target(name: "MeterKit"),
        .testTarget(name: "MeterKitTests", dependencies: ["MeterKit"]),
    ]
)
