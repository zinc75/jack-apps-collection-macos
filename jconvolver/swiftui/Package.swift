// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (jconvolver and fconvolver, by Fons Adriaensen).
import Foundation
import PackageDescription

// libsndfile and the codecs it needs are linked statically by SoundFileKit, from the libraries of the repository, as
// universal libraries (arm64 and x86_64). Build them first, with libs/<name>/build_universal.sh. The targets that use it
// need the headers of that folder.
let libs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../libs/build/universal").standardized.path
let headers = ["-Xcc", "-I\(libs)/include"]

let package = Package(
    name: "JConvolver",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libjack loaded at run time, shared with the other tools of the repository.
        .package(path: "../../shared/JackBridge"),
        // Sound files read with libsndfile, MIT, shared with the other tools.
        .package(path: "../../shared/SoundFileKit"),
        // The waveform of a file, level meters, the look (dark, system, light) and the accent, and the glass and badges of the
        // matrix, MIT, shared with the other tools.
        .package(path: "../../shared/WaveformKit"),
        .package(path: "../../shared/AppearanceKit"),
        .package(path: "../../shared/MatrixKit"),
        // The plots of an impulse response (waveform, spectrum, phase), MIT, shared with the other tools.
        .package(path: "../../shared/PlotKit"),
    ],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CJConvolverPty"),
        // libsamplerate, linked statically, to bring an impulse response to the rate of the server.
        .target(
            name: "CSamplerate",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(libs)/include"])],
            linkerSettings: [.unsafeFlags(["-L\(libs)/lib", "-lsamplerate"])]
        ),
        // Logic without any UI: the configuration files, what the programs say, the command lines, running them,
        // measuring their load, reading the sound files. Unit tested.
        .target(
            name: "JConvolverKit",
            dependencies: ["CJConvolverPty", "CSamplerate", .product(name: "SoundFileKit", package: "SoundFileKit"), .product(name: "CSndfile", package: "SoundFileKit"),
                           .product(name: "JackBridge", package: "JackBridge")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        // The SwiftUI application. As in JackMate, UI code is main-actor isolated by default.
        .executableTarget(
            name: "JackConvolver",
            dependencies: [
                "JConvolverKit",
                .product(name: "SoundFileKit", package: "SoundFileKit"),
                .product(name: "JackBridge", package: "JackBridge"),
                .product(name: "WaveformKit", package: "WaveformKit"),
                .product(name: "AppearanceKit", package: "AppearanceKit"),
                .product(name: "MatrixKit", package: "MatrixKit"),
                .product(name: "PlotKit", package: "PlotKit"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"] + headers)]
        ),
        .testTarget(name: "JConvolverKitTests", dependencies: ["JConvolverKit", .product(name: "SoundFileKit", package: "SoundFileKit")], swiftSettings: [.unsafeFlags(headers)]),
    ]
)
