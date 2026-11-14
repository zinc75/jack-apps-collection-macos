// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import Foundation
import PackageDescription

// The JACK backend of the klick engine is a static library built by klick/engine/build_jack.sh (klick/build/libklickjack.a);
// the engine of klick it builds on is the one of the core (klick/klick-tempo/klick/build/libklickengine.a, linked by the core package).
let jackDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build").path

let package = Package(
    name: "KlickJack",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "KlickJack", targets: ["KlickJack"]),
        .executable(name: "KlickCollection", targets: ["KlickCollection"]),
    ],
    dependencies: [
        // The core of the application of the family: the window, the model and the engine of klick. A local path, so that the unsafe
        // link flags of its engine are accepted.
        .package(path: "../klick-tempo/klick/swiftui"),
        // (The copies of the shared packages that the core uses: a package graph has one MatrixKit, and the core depends on its own.)
        .package(path: "../klick-tempo/shared/MatrixKit"),
        .package(path: "../klick-tempo/shared/AppearanceKit"),
        // The JackMoebius daemon client (which application stands behind a client: its icon), MIT, shared with Jack Capture.
        .package(path: "../../shared/JackBridge"),
    ],
    targets: [
        // The C interface of the JACK backend (klick_jack.h) and the link settings of its static library.
        .target(
            name: "CKlickJack",
            dependencies: [.product(name: "CKlickEngine", package: "swiftui")],
            linkerSettings: [
                .unsafeFlags(["-L\(jackDirectory)"]),
                .linkedLibrary("klickjack"),
                .linkedLibrary("c++"),
            ]
        ),
        // The backend, its page of the output settings and the menu of the pill. As in the core, UI code is main-actor isolated by default.
        .target(
            name: "KlickJack",
            dependencies: [
                "CKlickJack",
                .product(name: "KlickUI", package: "swiftui"),
                .product(name: "KlickKit", package: "swiftui"),
                .product(name: "KlickEngine", package: "swiftui"),
                .product(name: "CKlickEngine", package: "swiftui"),
                .product(name: "MatrixKit", package: "MatrixKit"),
                .product(name: "AppearanceKit", package: "AppearanceKit"),
                .product(name: "JackBridge", package: "JackBridge"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])]
        ),
        // The application of the collection: the core of Klick with the JACK backend added to CoreAudio. Its name, its colour and the
        // backends it offers; nothing else.
        // (Named differently from the target and the product of the core: names are unique in the package graph. The bundle makes it
        // "Klick" again, see build.sh.)
        .executableTarget(
            name: "KlickCollection",
            dependencies: [
                "KlickJack",
                .product(name: "KlickUI", package: "swiftui"),
                .product(name: "AppearanceKit", package: "AppearanceKit"),
            ]
        ),
        .testTarget(
            name: "KlickJackTests",
            dependencies: [
                "KlickJack",
                .product(name: "KlickKit", package: "swiftui"),
                .product(name: "KlickEngine", package: "swiftui"),
            ]
        ),
    ]
)
