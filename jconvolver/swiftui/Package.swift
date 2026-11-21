// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the programs this interface drives (jconvolver and fconvolver, by Fons Adriaensen).
import Foundation
import PackageDescription

// libsndfile and the codecs it needs (FLAC, Ogg Vorbis, Opus, MP3), linked statically from the libraries of the
// repository, as universal libraries (arm64 and x86_64). Build them first, with libs/<name>/build_universal.sh.
let libs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../libs/build/universal").standardized.path
let headers = ["-Xcc", "-I\(libs)/include"]
let sndfileLink = ["-L\(libs)/lib", "-lsndfile", "-lmp3lame", "-lFLAC", "-lvorbisenc", "-lvorbis", "-logg", "-lopus", "-lmpg123", "-lm"]

let package = Package(
    name: "JConvolver",
    platforms: [.macOS("15.0")],
    dependencies: [
        // The waveform of a file, MIT, shared with the other tools; its source of samples is read here with libsndfile.
        .package(path: "../../shared/WaveformKit"),
    ],
    targets: [
        // Runs a program in a pseudo-terminal (Swift cannot fork).
        .target(name: "CJConvolverPty"),
        // libsndfile, for the Swift code. The header comes from the libraries of the repository.
        .target(
            name: "CSndfile",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(libs)/include"])],
            linkerSettings: [.unsafeFlags(sndfileLink)]
        ),
        // Logic without any UI: the configuration files, what the programs say, the command lines, running them,
        // measuring their load, reading the sound files. Unit tested.
        .target(
            name: "JConvolverKit",
            dependencies: ["CJConvolverPty", "CSndfile", .product(name: "WaveformKit", package: "WaveformKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        .testTarget(name: "JConvolverKitTests", dependencies: ["JConvolverKit"], swiftSettings: [.unsafeFlags(headers)]),
    ]
)
