// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class CurveDataTests: XCTestCase {
    func testColumnsKeepEveryPeak() {
        var s = [Float](repeating: 0.01, count: 1000)
        s[503] = 0.9
        s[777] = -0.7
        let data = CurveData(samples: s, sampleRate: 48000)
        let c = data.columns(from: 0, to: 1000, width: 10)
        XCTAssertEqual(c.maximums.max(), 0.9)
        XCTAssertEqual(c.minimums.min(), -0.7)
        XCTAssertEqual(c.maximums[5], 0.9)
        XCTAssertEqual(c.minimums[7], -0.7)
    }

    func testZoomedInColumnsFollowTheSamples() {
        let data = CurveData(samples: [0, 1, 0, -1], sampleRate: 48000)
        let c = data.columns(from: 0, to: 4, width: 8)
        XCTAssertEqual(c.maximums.count, 8)
        XCTAssertEqual(c.maximums[2], 1)
        XCTAssertEqual(c.minimums[6], -1)
    }

    func testDecibelScale() {
        let scale = CurveScale.decibels(floorDB: -90)
        XCTAssertEqual(scale.height(of: 1, reference: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(scale.height(of: -0.001, reference: 1), -(30.0 / 90.0), accuracy: 1e-6)
        XCTAssertEqual(scale.height(of: 0, reference: 1), 0)
        XCTAssertEqual(scale.height(of: 1e-9, reference: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(CurveScale.linear.height(of: 0.5, reference: 1), 0.5, accuracy: 1e-9)
    }
}
