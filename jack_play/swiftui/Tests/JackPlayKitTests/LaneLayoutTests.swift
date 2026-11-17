// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

final class LaneLayoutTests: XCTestCase {
    func testTheLanesGetThinnerAndGoInColumnsWithTheChannels() {
        let expected: [(channels: Int, columns: Int, lane: CGFloat)] = [
            (1, 1, 60), (2, 1, 60), (3, 1, 45), (8, 1, 45), (9, 1, 45), (12, 1, 45),
            (13, 2, 45), (24, 2, 45), (25, 3, 45), (36, 3, 45), (37, 4, 45), (64, 4, 45), (65, 4, 45), (128, 4, 45),
        ]
        for e in expected {
            let l = LaneLayout(channels: e.channels)
            XCTAssertEqual(l.columns, e.columns, "\(e.channels) channels")
            XCTAssertEqual(l.laneHeight, e.lane, "\(e.channels) channels")
        }
    }

    func testTheColumnsHoldEveryChannelOnceInOrder() {
        for n in [1, 2, 7, 12, 13, 17, 33, 36, 64, 65, 100, 128] {
            let l = LaneLayout(channels: n)
            let all = (0..<l.columns).flatMap { Array(l.range($0)) }
            XCTAssertEqual(all, Array(0..<n), "\(n) channels")
        }
        XCTAssertEqual(LaneLayout(channels: 64).range(0), 0..<16)
        XCTAssertEqual(LaneLayout(channels: 64).range(3), 48..<64)
        XCTAssertEqual(LaneLayout(channels: 36).range(2), 24..<36)
    }

    func testTheHeightIsThatOfTheLongestColumn() {
        XCTAssertEqual(LaneLayout(channels: 64).height, 16 * 45)
        XCTAssertEqual(LaneLayout(channels: 36).height, 12 * 45)
        XCTAssertEqual(LaneLayout(channels: 2).height, 120)
    }
}
