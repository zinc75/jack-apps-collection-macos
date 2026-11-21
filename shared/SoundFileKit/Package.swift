// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import Foundation
import PackageDescription

// libsndfile and the codecs it needs (FLAC, Ogg Vorbis, Opus, MP3), linked statically from the libraries of the
// repository, as universal libraries (arm64 and x86_64). Build them first, with libs/<name>/build_universal.sh.
let libs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../libs/build/universal").standardized.path
let headers = ["-Xcc", "-I\(libs)/include"]
let sndfileLink = ["-L\(libs)/lib", "-lsndfile", "-lmp3lame", "-lFLAC", "-lvorbisenc", "-lvorbis", "-logg", "-lopus", "-lmpg123", "-lm"]

let package = Package(
    name: "SoundFileKit",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SoundFileKit", targets: ["SoundFileKit"]),
        // libsndfile itself, for the code of an application that has to write files or use a function the package does not wrap.
        .library(name: "CSndfile", targets: ["CSndfile"]),
    ],
    dependencies: [
        // The source of samples that the waveform reads.
        .package(path: "../WaveformKit"),
    ],
    targets: [
        // libsndfile, for the Swift code. The header comes from the libraries of the repository.
        .target(
            name: "CSndfile",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(libs)/include"])],
            linkerSettings: [.unsafeFlags(sndfileLink)]
        ),
        .target(
            name: "SoundFileKit",
            dependencies: ["CSndfile", .product(name: "WaveformKit", package: "WaveformKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
        .testTarget(
            name: "SoundFileKitTests",
            dependencies: ["SoundFileKit", "CSndfile", .product(name: "WaveformKit", package: "WaveformKit")],
            swiftSettings: [.unsafeFlags(headers)]
        ),
    ]
)
