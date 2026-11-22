// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "PlotKit",
    platforms: [.macOS("15.0")],
    products: [.library(name: "PlotKit", targets: ["PlotKit"])],
    targets: [
        .target(name: "PlotKit"),
        .testTarget(name: "PlotKitTests", dependencies: ["PlotKit"]),
    ]
)
