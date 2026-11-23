// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

@MainActor
final class PlayHubTests: XCTestCase {
    func testTheSessionsTakeTheLowestFreeNumber() async {
        let hub = PlayHub(defaults: nil)
        XCTAssertEqual(hub.takeSessionNumber(), 1)
        XCTAssertEqual(hub.takeSessionNumber(), 2)
        XCTAssertEqual(hub.takeSessionNumber(), 3)
        hub.releaseSessionNumber(2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(hub.takeSessionNumber(), 2, "the number that was given back is the next one")
        XCTAssertEqual(hub.takeSessionNumber(), 4)
    }

    func testANumberIsKeptWhileTheProgramsOfTheSessionAreAlive() async {
        let hub = PlayHub(defaults: nil)
        _ = hub.takeSessionNumber()
        let two = hub.takeSessionNumber()
        var alive = true
        hub.releaseSessionNumber(two, whenFree: { !alive })
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(hub.takeSessionNumber(), 3, "its programs are still there: a new session cannot be named like them")
        alive = false
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(hub.takeSessionNumber(), 2)
    }

    func testOnlyTheFirstSessionReadsTheSavedState() {
        let hub = PlayHub(defaults: nil)
        XCTAssertTrue(hub.claimSavedState())
        XCTAssertFalse(hub.claimSavedState())
        XCTAssertFalse(hub.claimSavedState())
    }

    func testThePlacementOfTheLevelsIsKept() {
        let suite = "jackplay.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let hub = PlayHub(defaults: defaults)
        XCTAssertEqual(hub.levelsPlacement, .inline)
        hub.levelsPlacement = .below
        XCTAssertEqual(PlayHub(defaults: defaults).levelsPlacement, .below)
    }

    func testEveryPlayerHearsTheChangesOfTheGraph() {
        let graph = PlaybackGraph()
        let first = graph.makeHandle(), second = graph.makeHandle()
        var heard = [0, 0]
        first.onChange = { heard[0] += 1 }
        second.onChange = { heard[1] += 1 }
        graph.notifyChange()
        XCTAssertEqual(heard, [1, 1])
        graph.notifyChange()
        XCTAssertEqual(heard, [2, 2], "one player does not take the call of another")
    }

    func testAPlayerThatIsGoneIsNotCalled() {
        let graph = PlaybackGraph()
        var heard = 0
        do {
            let gone = graph.makeHandle()
            gone.onChange = { heard += 1 }
        }
        graph.notifyChange()
        XCTAssertEqual(heard, 0)
    }
}

final class OutsideOpenPlanTests: XCTestCase {
    func testWithNoSessionInFrontTheFilesOpenANewOne() {
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: false, isBlank: true, isPlaying: false, atLaunch: false), .newSession)
    }

    func testASessionWithNothingInItTakesTheFiles() {
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: true, isBlank: true, isPlaying: false, atLaunch: false), .useSession)
    }

    func testASessionWithAListIsAskedAbout() {
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: true, isBlank: false, isPlaying: false, atLaunch: false), .ask)
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: true, isBlank: false, isPlaying: true, atLaunch: false), .ask)
    }

    func testAtLaunchTheListOfTheLastTimeIsReplacedWithoutAsking() {
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: true, isBlank: false, isPlaying: false, atLaunch: true), .useSession)
        XCTAssertEqual(OutsideOpenPlan.plan(hasTarget: true, isBlank: false, isPlaying: true, atLaunch: true), .ask, "what plays is never replaced without asking")
    }
}
