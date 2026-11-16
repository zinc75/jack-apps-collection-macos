// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "WaveformKit",
    platforms: [.macOS("15.0")],
    products: [.library(name: "WaveformKit", targets: ["WaveformKit"])],
    targets: [
        .target(name: "WaveformKit"),
        .testTarget(name: "WaveformKitTests", dependencies: ["WaveformKit"]),
    ]
)
