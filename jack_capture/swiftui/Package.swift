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
            dependencies: ["JackCaptureKit", .product(name: "MatrixKit", package: "MatrixKit"), .product(name: "MeterKit", package: "MeterKit")],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])]
        ),
        .testTarget(name: "JackCaptureKitTests", dependencies: ["JackCaptureKit", .product(name: "MeterKit", package: "MeterKit")]),
    ]
)
