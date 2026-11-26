// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (jack_capture).
import PackageDescription

let package = Package(
    name: "JackCapture",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libjack loaded at run time (shared with the other tools of the repository).
        .package(path: "../../shared/JackBridge"),
        // Look and feel of the matrix (glass, badges, points, frozen panes), MIT, shared with the other tools.
        .package(path: "../../shared/MatrixKit"),
        // Level meters (model, ballistics, bars), MIT, shared with the other tools; the scales stay in the tools.
        .package(path: "../../shared/MeterKit"),
        // The look (dark, system, light) and the accent, MIT, shared with the other tools.
        .package(path: "../../shared/AppearanceKit"),
        // The sessions of an application in windows, the menu bar and the Dock, MIT, shared with the other tools.
        .package(path: "../../shared/SessionKit"),
        // Looks for a newer release on GitHub and opens its package in the Installer, MIT, shared with the other tools.
        .package(path: "../../shared/UpdateKit"),
    ],
    targets: [
        // Logic without any UI: settings, command line, file names, recorder state. Unit tested.
        .target(name: "JackCaptureKit", dependencies: [
            .product(name: "JackBridge", package: "JackBridge"),
            .product(name: "MeterKit", package: "MeterKit"),
        ]),
        // The SwiftUI application. As in JackMate, UI code is main-actor isolated by default.
        .executableTarget(
            name: "JackCapture",
            dependencies: [
                "JackCaptureKit",
                .product(name: "MatrixKit", package: "MatrixKit"),
                .product(name: "MeterKit", package: "MeterKit"),
                .product(name: "AppearanceKit", package: "AppearanceKit"),
                .product(name: "SessionKit", package: "SessionKit"),
                .product(name: "UpdateKit", package: "UpdateKit"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])]
        ),
        .testTarget(name: "JackCaptureKitTests", dependencies: ["JackCaptureKit", .product(name: "MeterKit", package: "MeterKit")]),
    ]
)
