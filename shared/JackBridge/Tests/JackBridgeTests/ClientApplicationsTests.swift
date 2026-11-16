// SPDX-License-Identifier: MIT

import XCTest
@testable import JackBridge

@MainActor
final class ClientApplicationsTests: XCTestCase {
    private func wait(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), what)
    }

    func testTheMetadataOfAClientGivesItsApplication() {
        let apps = ClientApplications(metadata: { $0 == "Safari" ? "com.apple.Safari" : nil }, daemonIsPresent: { false })
        var calls = 0
        apps.onChange = { calls += 1 }
        apps.update(clients: ["Safari", "Other"])
        XCTAssertEqual(apps.bundles, ["Safari": "com.apple.Safari"])
        XCTAssertEqual(calls, 1)
        apps.update(clients: ["Safari", "Other"])
        XCTAssertEqual(calls, 1, "nothing new, nothing said")
    }

    func testTheDaemonIsAskedForTheOthersAndTheNameMayDifferInCase() async {
        let apps = ClientApplications(metadata: { _ in nil }, daemonKeys: { ["Reaper": "com.cockos.reaper", "Music": "com.apple.Music"] },
                                      daemonIsPresent: { true }, retryDelay: 1_000_000)
        apps.update(clients: ["REAPER", "Music", "Unknown"])
        await wait("the applications are found") { apps.bundles.count == 2 }
        XCTAssertEqual(apps.bundles["REAPER"], "com.cockos.reaper")
        XCTAssertEqual(apps.bundles["Music"], "com.apple.Music")
        XCTAssertNil(apps.bundles["Unknown"])
    }

    func testTheDaemonIsAskedThreeTimesAtMostForASetOfClients() async {
        final class Counter: @unchecked Sendable { var n = 0; let lock = NSLock(); func bump() { lock.lock(); n += 1; lock.unlock() } }
        let counter = Counter()
        let apps = ClientApplications(metadata: { _ in nil }, daemonKeys: { counter.bump(); return [:] }, daemonIsPresent: { true }, retryDelay: 1_000_000)
        apps.update(clients: ["Nobody"])
        try? await Task.sleep(nanoseconds: 300_000_000)
        apps.update(clients: ["Nobody"])
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(counter.n, 3)
        // A new set of clients starts again.
        apps.update(clients: ["Nobody", "Else"])
        await wait("asked again") { counter.n > 3 }
    }

    func testNothingHappensWithoutTheDaemon() async {
        let apps = ClientApplications(metadata: { _ in nil }, daemonKeys: { XCTFail("asked"); return [:] }, daemonIsPresent: { false })
        apps.update(clients: ["Nobody"])
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(apps.bundles.isEmpty)
    }

    func testResetForgetsWhatWasFound() {
        let apps = ClientApplications(metadata: { _ in "x" }, daemonIsPresent: { false })
        apps.update(clients: ["A"])
        apps.reset()
        XCTAssertTrue(apps.bundles.isEmpty)
    }
}
