// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (zita-j2n and zita-n2j, from zita-njbridge).
import PackageDescription

let package = Package(
    name: "ZitaNetworkBridge",
    platforms: [.macOS("15.0")],
    targets: [
        // Logic without any UI: what the programs say, the command lines, the settings. Unit tested.
        .target(name: "ZitaBridgeKit"),
        .testTarget(name: "ZitaBridgeKitTests", dependencies: ["ZitaBridgeKit"]),
    ]
)
