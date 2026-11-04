// SPDX-License-Identifier: MIT

import XCTest
@testable import MeterKit

final class ChannelMeterTests: XCTestCase {
    func testTheLevelRisesAtOnce() {
        let old = ChannelMeter(level: 0.2, peak: 0.3, clipped: false)
        let new = ChannelMeter(level: 0.9, peak: 0.95, clipped: false)
        XCTAssertEqual(old.following(new), ChannelMeter(level: 0.9, peak: 0.95, clipped: false))
    }

    func testTheLevelFallsALittleAtATime() {
        let old = ChannelMeter(level: 1, peak: 1, clipped: false)
        let silent = ChannelMeter(level: 0, peak: 0.4, clipped: false)
        XCTAssertEqual(old.following(silent).level, ChannelMeter.defaultFall, accuracy: 1e-12)
        XCTAssertEqual(old.following(silent).following(silent).level, ChannelMeter.defaultFall * ChannelMeter.defaultFall, accuracy: 1e-12)
        XCTAssertEqual(old.following(silent).peak, 0.4)
    }

    func testTheClipMarkStaysWhileThePeakIsFullScale() {
        let clipped = ChannelMeter(level: 1, peak: 1, clipped: true)
        XCTAssertTrue(clipped.following(ChannelMeter(level: 0.5, peak: 1, clipped: false)).clipped)
        XCTAssertFalse(clipped.following(ChannelMeter(level: 0.5, peak: 0.6, clipped: false)).clipped)
    }

    func testAChannelWithoutHistoryTakesTheNewReading() {
        let old = [ChannelMeter(level: 1, peak: 1, clipped: false)]
        let new = [ChannelMeter(level: 0, peak: 0, clipped: false), ChannelMeter(level: 0.4, peak: 0.5, clipped: false)]
        let result = old.following(new)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].level, ChannelMeter.defaultFall, accuracy: 1e-12)
        XCTAssertEqual(result[1], new[1])
    }

    func testAScaleIsWhatTheToolSays() {
        struct Linear: MeterScale { func fraction(db: Double) -> Double { min(max((db + 60) / 60, 0), 1) } }
        let scale: any MeterScale = Linear()
        XCTAssertEqual(scale.fraction(db: -30), 0.5, accuracy: 1e-12)
    }
}
