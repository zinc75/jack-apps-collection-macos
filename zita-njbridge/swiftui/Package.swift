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
        // The look (dark, system, light) and the accent, and the glass and badges of the matrix, MIT, shared with the other tools.
        .package(path: "../../shared/AppearanceKit"),
        .package(path: "../../shared/MatrixKit"),
    ],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CZitaPty"),
        // Logic without any UI: what the programs say, the command lines, the settings, running them, the wiring. Unit tested.
        .target(name: "ZitaBridgeKit", dependencies: ["CZitaPty", .product(name: "JackBridge", package: "JackBridge")]),
        // The SwiftUI application. As in JackMate, UI code is main-actor isolated by default.
        .executableTarget(
            name: "ZitaNetworkBridge",
            dependencies: [
                "ZitaBridgeKit",
                .product(name: "AppearanceKit", package: "AppearanceKit"),
                .product(name: "MatrixKit", package: "MatrixKit"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])]
        ),
        .testTarget(name: "ZitaBridgeKitTests", dependencies: ["ZitaBridgeKit", .product(name: "JackBridge", package: "JackBridge")]),
    ]
)
