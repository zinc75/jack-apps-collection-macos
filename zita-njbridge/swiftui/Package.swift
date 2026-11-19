// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (zita-j2n and zita-n2j, from zita-njbridge).
import PackageDescription

let package = Package(
    name: "ZitaNetworkBridge",
    platforms: [.macOS("15.0")],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CZitaPty"),
        // Logic without any UI: what the programs say, the command lines, the settings, running them. Unit tested.
        .target(name: "ZitaBridgeKit", dependencies: ["CZitaPty"]),
        .testTarget(name: "ZitaBridgeKitTests", dependencies: ["ZitaBridgeKit"]),
    ]
)
