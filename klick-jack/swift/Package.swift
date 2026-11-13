// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import Foundation
import PackageDescription

// The JACK backend of the klick engine is a static library built by klick-jack/engine/build_jack.sh (klick-jack/build/libklickjack.a);
// the engine of klick it builds on is the one of the core (klick/build/libklickengine.a, linked by the core package).
let jackDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build").path

let package = Package(
    name: "KlickJack",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "KlickJack", targets: ["KlickJack"]),
    ],
    dependencies: [
        // The core of the application of the family: the window, the model and the engine of klick. A local path, so that the unsafe
        // link flags of its engine are accepted.
        .package(path: "../../klick/swiftui"),
        .package(path: "../../shared/MatrixKit"),
        .package(path: "../../shared/AppearanceKit"),
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
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])]
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
