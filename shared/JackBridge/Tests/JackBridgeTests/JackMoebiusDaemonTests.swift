// SPDX-License-Identifier: MIT

import XCTest
@testable import JackBridge

/// The reply of the JackMoebius daemon (a list of applications with their bundle identifier and the name of their JACK client).
final class JackMoebiusDaemonTests: XCTestCase {
    private let rows: [[String: Any]] = [
        ["key": "com.apple.Music", "name": "Musique", "pid": 100, "out_exposed": true, "future_field": [1, 2]],
        ["key": "com.cockos.reaper", "name": "Reaper", "pid": 200],
        ["key": "path:/opt/tool/bin/tool", "name": "tool", "pid": 300],
        ["name": "no key"],
    ]

    func testTheKeysAreReadByClientName() {
        let keys = JackMoebiusDaemon.parseApps(rows)
        XCTAssertEqual(keys["Musique"], "com.apple.Music")
        XCTAssertEqual(keys["Reaper"], "com.cockos.reaper")
        XCTAssertNil(keys["tool"], "an application with no bundle has no icon to give")
        XCTAssertNil(keys["no key"])
    }

    func testABadReplyGivesNothing() {
        XCTAssertTrue(JackMoebiusDaemon.parseApps(nil).isEmpty)
        XCTAssertTrue(JackMoebiusDaemon.parseApps("oops").isEmpty)
    }

    func testTheNameMayDifferInCase() {
        let keys = JackMoebiusDaemon.parseApps(rows)
        XCTAssertEqual(JackMoebiusDaemon.key(forClient: "REAPER", in: keys), "com.cockos.reaper")
        XCTAssertEqual(JackMoebiusDaemon.key(forClient: "Musique", in: keys), "com.apple.Music")
        XCTAssertNil(JackMoebiusDaemon.key(forClient: "Other", in: keys))
    }
}
