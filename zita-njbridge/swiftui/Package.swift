// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (zita-j2n and zita-n2j, from zita-njbridge).
import PackageDescription

let package = Package(
    name: "ZitaNetworkBridge",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libjack loaded at run time, shared with the other tools of the repository.
        .package(path: "../../shared/JackBridge"),
    ],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CZitaPty"),
        // Logic without any UI: what the programs say, the command lines, the settings, running them, the wiring. Unit tested.
        .target(name: "ZitaBridgeKit", dependencies: ["CZitaPty", .product(name: "JackBridge", package: "JackBridge")]),
        .testTarget(name: "ZitaBridgeKitTests", dependencies: ["ZitaBridgeKit", .product(name: "JackBridge", package: "JackBridge")]),
    ]
)
