// SPDX-License-Identifier: MIT

import XCTest
@testable import JackBridge

final class JackBridgeTests: XCTestCase {
    /// Without a running server the client does not open, and says so instead of crashing.
    func testOpenFailsCleanlyWithoutServer() {
        setenv("JACK_DEFAULT_SERVER", "jackbridge-test-no-such-server", 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }
        let bridge = JackBridgeWrapper()
        XCTAssertThrowsError(try bridge.open(clientName: "bridge-test"))
        XCTAssertFalse(bridge.isConnected)
        XCTAssertTrue(bridge.getPorts().isEmpty)
    }
}
