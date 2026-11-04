// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class SourceCheckTests: XCTestCase {
    private let available: Set<String> = ["system:capture_1", "system:capture_2", "Musique:out_1", "Reaper:in_1"]

    private func check(_ sources: [[String]], channels: Int, autoConnect: Bool = true,
                       inputs: [String: [String]] = ["Reaper:in_1": ["system:capture_1"]]) -> SourceCheck {
        SourceCheck(sources: sources, channels: channels, autoConnect: autoConnect, available: available, inputConnections: inputs)
    }

    func testEveryChannelFedByAPresentPortIsClean() {
        XCTAssertTrue(check([["system:capture_1"], ["Musique:out_1"]], channels: 2).isClean)
    }

    func testNoChosenSourceMeansNothingIsConnected() {
        let result = check([], channels: 4)
        XCTAssertEqual(result.unassigned, [1, 2, 3, 4])
        XCTAssertFalse(result.isClean)
        XCTAssertTrue(check([], channels: 4, autoConnect: false).isClean, "left to the patchbay")
    }

    func testAChannelLeftEmptyAmongOthersIsReported() {
        let result = check([["system:capture_1"], [], ["Musique:out_1"]], channels: 4)
        XCTAssertEqual(result.unassigned, [2, 4])
        XCTAssertFalse(result.isClean)
    }

    func testAPortWhoseClientIsGoneIsReported() {
        let result = check([["system:capture_1"], ["Ardour:out_1"]], channels: 2)
        XCTAssertEqual(result.problems, [.init(channel: 2, port: "Ardour:out_1", kind: .absent)])
    }

    func testAnInputPortWithNothingConnectedIsReported() {
        let result = check([["Reaper:in_1"], ["Reaper:in_1"]], channels: 2, inputs: ["Reaper:in_1": []])
        XCTAssertEqual(result.problems.map(\.kind), [.nothingConnected, .nothingConnected])
        XCTAssertTrue(check([["Reaper:in_1"]], channels: 1).isClean)
    }

    func testNothingIsCheckedWhenTheConnectionsAreLeftToThePatchbay() {
        XCTAssertTrue(check([["Ardour:out_1"], []], channels: 2, autoConnect: false).isClean)
    }

    func testTheSourcesBeyondTheChannelCountAreIgnored() {
        XCTAssertTrue(check([["system:capture_1"], ["Ardour:out_1"]], channels: 1).isClean)
    }

    func testDescriptionsNameChannelsAndPorts() {
        let lines = check([["Ardour:out_1"], []], channels: 3).descriptions
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("2") && lines[0].contains("3") && lines[0].contains("voies"))
        XCTAssertTrue(lines[1].contains("Ardour:out_1") && lines[1].contains("1"))
    }
}
