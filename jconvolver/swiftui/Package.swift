// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (jconvolver and fconvolver, by Fons Adriaensen).
import PackageDescription

let package = Package(
    name: "JConvolver",
    platforms: [.macOS("15.0")],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CJConvolverPty"),
        // Logic without any UI: the configuration files, what the programs say, the command lines, running them,
        // measuring their load. Unit tested.
        .target(name: "JConvolverKit", dependencies: ["CJConvolverPty"]),
        .testTarget(name: "JConvolverKitTests", dependencies: ["JConvolverKit"]),
    ]
)
