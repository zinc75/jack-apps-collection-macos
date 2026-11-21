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
        // Sound files read with libsndfile, MIT, shared with the other tools.
        .package(path: "../../shared/SoundFileKit"),
    ],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CJConvolverPty"),
        // Logic without any UI: the configuration files, what the programs say, the command lines, running them,
        // measuring their load, reading the sound files. Unit tested.
        .target(
            name: "JConvolverKit",
            dependencies: ["CJConvolverPty", .product(name: "SoundFileKit", package: "SoundFileKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        .testTarget(name: "JConvolverKitTests", dependencies: ["JConvolverKit", .product(name: "SoundFileKit", package: "SoundFileKit")], swiftSettings: [.unsafeFlags(headers)]),
    ]
)
