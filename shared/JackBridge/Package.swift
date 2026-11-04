// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "JackBridge",
    platforms: [.macOS("11.0")],
    products: [.library(name: "JackBridge", targets: ["JackBridge"])],
    targets: [
        // libjack loaded at run time with dlopen: nothing is linked against it.
        .target(name: "CJackBridge"),
        .target(name: "JackBridge", dependencies: ["CJackBridge"]),
        .testTarget(name: "JackBridgeTests", dependencies: ["JackBridge"]),
    ]
)
