// SPDX-License-Identifier: MIT

import XCTest
@testable import WaveformKit

final class TimeRulerTests: XCTestCase {
    func testAClockIsCutNotRounded() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(59.99), "0:59")
        XCTAssertEqual(TimeFormat.clock(108.4), "1:48")
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.clock(3725.9), "1:02:05")
    }

    func testTenths() {
        XCTAssertEqual(TimeFormat.clock(72.46, tenths: true), "1:12.4")
        XCTAssertEqual(TimeFormat.clock(0.05, tenths: true), "0:00.0")
        XCTAssertEqual(TimeFormat.clock(9.99, tenths: true), "0:09.9")
    }

    func testBadValuesReadZero() {
        XCTAssertEqual(TimeFormat.clock(-5), "0:00")
        XCTAssertEqual(TimeFormat.clock(.nan), "0:00")
        XCTAssertEqual(TimeFormat.clock(.infinity), "0:00")
    }

    func testTheStepGrowsWithTheDuration() {
        XCTAssertEqual(TimeRuler.step(duration: 108, width: 700), 10)
        XCTAssertEqual(TimeRuler.step(duration: 5, width: 700), 0.5)
        XCTAssertEqual(TimeRuler.step(duration: 3600, width: 700), 600)
        XCTAssertNil(TimeRuler.step(duration: 0, width: 700))
        XCTAssertNil(TimeRuler.step(duration: 100, width: 0))
    }

    func testTicksStayInsideTheFileAndFarEnoughApart() {
        for (duration, width) in [(108.4, 700.0), (42.3, 300.0), (7200.0, 900.0), (0.8, 500.0)] {
            let ticks = TimeRuler.ticks(duration: duration, width: width)
            XCTAssertFalse(ticks.isEmpty)
            XCTAssertEqual(ticks.first?.time, 0)
            XCTAssertLessThanOrEqual(ticks.last!.time, duration)
            for t in ticks { XCTAssertLessThanOrEqual(t.fraction, 1) }
            if ticks.count > 1 {
                XCTAssertGreaterThanOrEqual((ticks[1].fraction - ticks[0].fraction) * width, 64 - 1e-9, "\(duration) s over \(width)")
            }
        }
    }

    func testTheLabelsOfAShortFileHaveTenths() {
        let ticks = TimeRuler.ticks(duration: 0.8, width: 500)
        XCTAssertEqual(ticks.first?.label, "0:00.0")
        XCTAssertTrue(ticks.contains { $0.label == "0:00.6" })
    }

    func testNoTicksWithoutADurationOrAWidth() {
        XCTAssertTrue(TimeRuler.ticks(duration: 0, width: 500).isEmpty)
        XCTAssertTrue(TimeRuler.ticks(duration: 10, width: 0).isEmpty)
    }
}
