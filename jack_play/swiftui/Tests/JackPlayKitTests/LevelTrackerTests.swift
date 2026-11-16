// SPDX-License-Identifier: GPL-3.0-or-later

import MeterKit
import XCTest
@testable import JackPlayKit

final class IECScaleTests: XCTestCase {
    func testThePointsOfTheScale() {
        XCTAssertEqual(IECScale.fraction(db: 0), 1)
        XCTAssertEqual(IECScale.fraction(db: 6), 1, "above full scale it stays at the top")
        XCTAssertEqual(IECScale.fraction(db: -20), 0.5, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -30), 0.3, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -40), 0.15, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -50), 0.075, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -60), 0.025, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -55), 0.05, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -70), 0)
        XCTAssertEqual(IECScale.fraction(db: -.infinity), 0)
    }

    func testTheScaleNeverGoesDown() {
        var last = -1.0
        for db in stride(from: -90.0, through: 6.0, by: 0.05) {
            let f = IECScale.fraction(db: db)
            XCTAssertGreaterThanOrEqual(f, last, "\(db) dB")
            last = f
        }
    }

    func testEveryPieceStartsWhereTheBeforeOneEnds() {
        // No jump anywhere: just either side of each change of slope the scale differs by what the slope allows.
        for edge in [-70.0, -60, -50, -40, -30, -20, 0] {
            let below = IECScale.fraction(db: edge - 1e-9), above = IECScale.fraction(db: edge)
            XCTAssertEqual(below, above, accuracy: 1e-6, "a jump at \(edge) dB")
        }
    }
}

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

    func testBeyondFullScaleClipsToo() {
        var tracker = LevelTracker()
        tracker.update(peaks: [1.06], now: t0)
        XCTAssertTrue(tracker.meters[0].clipped, "a floating point file, or a converter, can go over")
        XCTAssertEqual(tracker.meters[0].level, 1)
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

    func testTheMetersGoBackToNothingOnReset() {
        var tracker = LevelTracker()
        tracker.update(peaks: [0.7, 0.7], now: t0)
        tracker.reset()
        XCTAssertTrue(tracker.meters.isEmpty)
    }

    func testTheChannelsKeepTheirOwnLevels() {
        // The first channel is 6 dB above the second one, as in the file: the meters say so.
        var tracker = LevelTracker()
        tracker.update(peaks: [0.5, 0.25], now: t0)
        XCTAssertGreaterThan(tracker.meters[0].level, tracker.meters[1].level)
        XCTAssertEqual(tracker.meters[0].level, IECScale.fraction(db: -6.0206), accuracy: 1e-4)
        XCTAssertEqual(tracker.meters[1].level, IECScale.fraction(db: -12.0412), accuracy: 1e-4)
    }
}
