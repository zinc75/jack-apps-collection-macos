// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the program this interface drives (jack_play, from rju-play).
import Foundation
import PackageDescription

// libsndfile and the codecs it needs are linked statically by SoundFileKit, from the libraries of the repository, as
// universal libraries (arm64 and x86_64). Build them first, with libs/<name>/build_universal.sh. The targets that use it
// need the headers of that folder.
let libs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../libs/build/universal").standardized.path
let headers = ["-Xcc", "-I\(libs)/include"]

let package = Package(
    name: "JackPlay",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libjack loaded at run time, shared with the other tools of the repository.
        .package(path: "../../shared/JackBridge"),
        // The waveform of the file, MIT, shared with the other tools.
        .package(path: "../../shared/WaveformKit"),
        // Sound files read with libsndfile, MIT, shared with the other tools.
        .package(path: "../../shared/SoundFileKit"),
        // Level meters (model, ballistics, bars), MIT, shared with the other tools; the scale stays in the tool.
        .package(path: "../../shared/MeterKit"),
        // The look (dark, system, light) and the accent, and the badges and glass of the matrix, MIT, shared with the other tools.
        .package(path: "../../shared/AppearanceKit"),
        .package(path: "../../shared/MatrixKit"),
    ],
    targets: [
        // Logic without any UI: files, player process, connections, state. Unit tested.
        .target(
            name: "JackPlayKit",
            dependencies: [
                .product(name: "SoundFileKit", package: "SoundFileKit"),
                .product(name: "JackBridge", package: "JackBridge"),
                .product(name: "MeterKit", package: "MeterKit"),
                .product(name: "WaveformKit", package: "WaveformKit"),
            ],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        // The SwiftUI application. As in JackMate, UI code is main-actor isolated by default.
        .executableTarget(
            name: "JackPlay",
            dependencies: [
                "JackPlayKit",
                .product(name: "SoundFileKit", package: "SoundFileKit"),
                .product(name: "AppearanceKit", package: "AppearanceKit"),
                .product(name: "MatrixKit", package: "MatrixKit"),
                .product(name: "MeterKit", package: "MeterKit"),
                .product(name: "WaveformKit", package: "WaveformKit"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"] + headers)]
        ),
        .testTarget(
            name: "JackPlayKitTests",
            dependencies: ["JackPlayKit", .product(name: "SoundFileKit", package: "SoundFileKit"), .product(name: "CSndfile", package: "SoundFileKit"), .product(name: "JackBridge", package: "JackBridge"), .product(name: "MeterKit", package: "MeterKit"), .product(name: "WaveformKit", package: "WaveformKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
    ]
)
