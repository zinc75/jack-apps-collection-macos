// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Licence of the program this interface drives (jack_play, from rju-play).
import Foundation
import PackageDescription

// libsndfile and the codecs it needs (FLAC, Ogg Vorbis, Opus, MP3), linked statically from the libraries of the
// repository, as universal libraries (arm64 and x86_64). Build them first, with libs/<name>/build_universal.sh.
let libs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../libs/build/universal").standardized.path
let headers = ["-Xcc", "-I\(libs)/include"]
let sndfileLink = ["-L\(libs)/lib", "-lsndfile", "-lmp3lame", "-lFLAC", "-lvorbisenc", "-lvorbis", "-logg", "-lopus", "-lmpg123", "-lm"]

let package = Package(
    name: "JackPlay",
    platforms: [.macOS("15.0")],
    dependencies: [
        // libjack loaded at run time, shared with the other tools of the repository.
        .package(path: "../../shared/JackBridge"),
        // The waveform of the file, MIT, shared with the other tools.
        .package(path: "../../shared/WaveformKit"),
        // Level meters (model, ballistics, bars), MIT, shared with the other tools; the scale stays in the tool.
        .package(path: "../../shared/MeterKit"),
    ],
    targets: [
        // libsndfile, for the Swift code. The header comes from the libraries of the repository.
        .target(
            name: "CSndfile",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(libs)/include"])],
            linkerSettings: [.unsafeFlags(sndfileLink)]
        ),
        // Logic without any UI: files, player process, connections, state. Unit tested.
        .target(
            name: "JackPlayKit",
            dependencies: [
                "CSndfile",
                .product(name: "JackBridge", package: "JackBridge"),
                .product(name: "MeterKit", package: "MeterKit"),
                .product(name: "WaveformKit", package: "WaveformKit"),
            ],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        .testTarget(
            name: "JackPlayKitTests",
            dependencies: ["JackPlayKit", "CSndfile", .product(name: "JackBridge", package: "JackBridge"), .product(name: "MeterKit", package: "MeterKit"), .product(name: "WaveformKit", package: "WaveformKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
    ]
)
