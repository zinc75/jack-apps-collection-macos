// SPDX-License-Identifier: MIT

import XCTest
@testable import WaveformKit

final class WaveformPeaksTests: XCTestCase {
    private func peaks(low: [Float], high: [Float]) -> WaveformPeaks {
        WaveformPeaks(channels: 1, totalFrames: Int64(low.count), sampleRate: 1, filledFrames: Int64(low.count), minimums: [low], maximums: [high])
    }

    func testBarsRegroupTheColumns() {
        let p = peaks(low: [-1, -2, -3, -4, -5, -6, -7, -8], high: [1, 2, 3, 4, 5, 6, 7, 8])
        let bars = p.bars(channel: 0, count: 4)
        XCTAssertEqual(bars.minimums, [-2, -4, -6, -8])
        XCTAssertEqual(bars.maximums, [2, 4, 6, 8])
    }

    func testBarsKeepTheExtremesWhenTheGroupsAreUneven() {
        let p = peaks(low: [-1, -9, -2, -3, -4], high: [1, 2, 3, 9, 4])
        let bars = p.bars(channel: 0, count: 2)
        XCTAssertEqual(bars.minimums, [-9, -4])
        XCTAssertEqual(bars.maximums, [2, 9])
    }

    func testMoreBarsThanColumnsRepeatsTheColumns() {
        let p = peaks(low: [-1, -2], high: [1, 2])
        let bars = p.bars(channel: 0, count: 4)
        XCTAssertEqual(bars.minimums, [-1, -1, -2, -2])
        XCTAssertEqual(bars.maximums, [1, 1, 2, 2])
    }

    func testColumnsNotReadYetDoNotPullABarTowardsZero() {
        // Half of a file read: the 4 first columns hold 0.5, the 4 others are still empty.
        let p = WaveformPeaks(channels: 1, totalFrames: 800, sampleRate: 1, filledFrames: 400,
                              minimums: [[0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0]], maximums: [[0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0]])
        let bars = p.bars(channel: 0, count: 3)   // groups of 2.67 columns: the second one reaches into the unread part
        XCTAssertEqual(bars.minimums, [0.5, 0.5, 0])
        XCTAssertEqual(bars.maximums, [0.5, 0.5, 0])
    }

    func testAnUnknownChannelHasNoBars() {
        let p = peaks(low: [-1], high: [1])
        XCTAssertTrue(p.bars(channel: 3, count: 4).minimums.isEmpty)
        XCTAssertEqual(p.peak(channel: 3), 0)
    }

    func testTheGeometryMapsAPointToAPosition() {
        XCTAssertEqual(WaveformGeometry.fraction(x: 50, width: 200), 0.25)
        XCTAssertEqual(WaveformGeometry.fraction(x: -10, width: 200), 0)
        XCTAssertEqual(WaveformGeometry.fraction(x: 500, width: 200), 1)
        XCTAssertEqual(WaveformGeometry.fraction(x: 5, width: 0), 0)
    }
}
