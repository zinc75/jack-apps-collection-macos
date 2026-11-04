// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
import MeterKit
@testable import JackCaptureKit

final class LevelTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testFullScaleIsTheTopOfTheScaleAndClips() {
        var tracker = LevelTracker()
        tracker.update(peaks: [1.0, 0.1], now: t0)
        XCTAssertEqual(tracker.meters[0].level, 1, accuracy: 1e-9)
        XCTAssertTrue(tracker.meters[0].clipped)
        XCTAssertEqual(tracker.meters[1].level, IECScale.fraction(db: -20), accuracy: 1e-6, "0.1 is -20 dBFS")
        XCTAssertFalse(tracker.meters[1].clipped)
    }

    func testSilenceIsAnEmptyBar() {
        var tracker = LevelTracker()
        tracker.update(peaks: [0, 0], now: t0)
        XCTAssertEqual(tracker.meters.map(\.level), [0, 0])
    }

    func testThePeakIsHeldThenFollowsTheLevelDown() {
        var tracker = LevelTracker()
        tracker.update(peaks: [0.5], now: t0)
        let high = tracker.meters[0].peak
        tracker.update(peaks: [0.01], now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(tracker.meters[0].peak, high, "still held after half a second")
        tracker.update(peaks: [0.01], now: t0.addingTimeInterval(LevelTracker.holdTime + 0.1))
        XCTAssertLessThan(tracker.meters[0].peak, high, "let go after the hold time")
    }

    func testTheLevelFallsGraduallyButRisesAtOnce() {
        var tracker = LevelTracker()
        tracker.update(peaks: [1.0], now: t0)
        tracker.update(peaks: [0], now: t0.addingTimeInterval(0.03))
        XCTAssertEqual(tracker.meters[0].level, ChannelMeter.defaultFall, accuracy: 1e-9)
        tracker.update(peaks: [0.5], now: t0.addingTimeInterval(0.06))
        XCTAssertEqual(tracker.meters[0].level, IECScale.fraction(db: 20 * log10(0.5)), accuracy: 1e-9)
    }

    func testAChangeOfChannelCountStartsAgain() {
        var tracker = LevelTracker()
        tracker.update(peaks: [1, 1, 1], now: t0)
        tracker.update(peaks: [0.1], now: t0.addingTimeInterval(0.03))
        XCTAssertEqual(tracker.meters.count, 1)
    }
}
