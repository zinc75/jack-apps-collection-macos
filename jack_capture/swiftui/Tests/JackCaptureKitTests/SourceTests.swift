// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class SourceAssignmentTests: XCTestCase {
    func testToggleSumsAndClears() {
        var a = SourceAssignment(channels: 3)
        a.toggle(port: "a:1", channel: 0)
        a.toggle(port: "b:1", channel: 0)
        a.toggle(port: "a:1", channel: 2)
        XCTAssertEqual(a.perChannel, [["a:1", "b:1"], [], ["a:1"]])
        XCTAssertEqual(a.usedCount, 2)
        XCTAssertEqual(a.summedCount, 1)
        XCTAssertTrue(a.isOn(port: "b:1", channel: 0))
        a.toggle(port: "b:1", channel: 0)
        XCTAssertFalse(a.isOn(port: "b:1", channel: 0))
        a.clear()
        XCTAssertEqual(a.usedCount, 0)
    }

    func testResizeKeepsTheFirstChannels() {
        var a = SourceAssignment([["a"], ["b"], ["c"]], channels: 3)
        a.resize(to: 2)
        XCTAssertEqual(a.perChannel, [["a"], ["b"]])
        a.resize(to: 4)
        XCTAssertEqual(a.perChannel, [["a"], ["b"], [], []])
        a.resize(to: 0)
        XCTAssertEqual(a.channelCount, 1)
    }

    func testFillWithInputs() {
        var a = SourceAssignment(channels: 3)
        a.fill(with: ["system:capture_1", "system:capture_2"])
        XCTAssertEqual(a.perChannel, [["system:capture_1"], ["system:capture_2"], []])
    }

    func testInitPadsAndTruncates() {
        XCTAssertEqual(SourceAssignment([["a"]], channels: 2).perChannel, [["a"], []])
        XCTAssertEqual(SourceAssignment([["a"], ["b"], ["c"]], channels: 2).perChannel, [["a"], ["b"]])
    }
}

final class JackGraphTests: XCTestCase {
    func testGroupingPutsTheCaptureClientFirst() {
        let g = JackGraph.groupClients(outputPorts: [
            "SuperCollider:out_1", "system:capture_1", "ardour:Master/audio_out 1",
            "SuperCollider:out_2", "system:capture_2", "ardour:Master/audio_out 2", "broken",
        ])
        XCTAssertEqual(g.map(\.name), ["system", "ardour", "SuperCollider"])
        XCTAssertTrue(g[0].isCapture)
        XCTAssertEqual(g[0].displayName, "system (capture)")
        XCTAssertEqual(g[1].ports, ["Master/audio_out 1", "Master/audio_out 2"])
        XCTAssertEqual(g[2].fullName(of: "out_1"), "SuperCollider:out_1")
    }

    func testInputPortsBelongToClientsThatAreSources() {
        let g = JackGraph.groupClients(
            outputPorts: ["system:capture_1", "ardour:out 1"],
            inputPorts: ["system:playback_1", "system:playback_2", "ardour:in 1", "meter:in"])
        XCTAssertEqual(g.map(\.name), ["system", "ardour"])   // "meter" has no output: not a source
        XCTAssertEqual(g[0].inputs, ["playback_1", "playback_2"])
        XCTAssertEqual(g[1].inputs, ["in 1"])
    }

    func testInputSources() {
        let m = JackGraph.inputSources(
            inputPorts: ["system:playback_1", "system:playback_2"],
            connections: [(from: "a:1", to: "system:playback_1"), (from: "b:1", to: "system:playback_1"), (from: "a:2", to: "other:in")])
        XCTAssertEqual(m["system:playback_1"], ["a:1", "b:1"])
        XCTAssertEqual(m["system:playback_2"], [])
        XCTAssertNil(m["other:in"])
    }

    func testHeardOutputs() {
        let heard = JackGraph.heardOutputs(connections: [
            (from: "ardour:out 1", to: "system:playback_1"),
            (from: "carla:out", to: "other:in"),
            (from: "ardour:out 2", to: "system:playback_2"),
        ])
        XCTAssertEqual(heard, ["ardour:out 1", "ardour:out 2"])
    }
}

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
