// SPDX-License-Identifier: MIT

import XCTest
@testable import MeterKit

final class IECScaleTests: XCTestCase {
    func testTheBreakpoints() {
        let table: [(Double, Double)] = [(-70, 0), (-60, 0.025), (-50, 0.075), (-40, 0.15), (-30, 0.3), (-20, 0.5), (0, 1)]
        for (db, expected) in table {
            XCTAssertEqual(IECScale.fraction(db: db), expected, accuracy: 1e-12, "\(db) dBFS")
        }
    }

    func testStraightLinesBetweenBreakpoints() {
        XCTAssertEqual(IECScale.fraction(db: -55), 0.05, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -10), 0.75, accuracy: 1e-12)
        XCTAssertEqual(IECScale.fraction(db: -65), 0.0125, accuracy: 1e-12)
    }

    func testOutsideTheScale() {
        XCTAssertEqual(IECScale.fraction(db: 6), 1)
        XCTAssertEqual(IECScale.fraction(db: -80), 0)
        XCTAssertEqual(IECScale.fraction(db: -.infinity), 0)
        XCTAssertEqual(IECScale.fraction(db: .nan), 0)
    }

    func testRisesAndHasNoJump() {
        var previous = 0.0
        var db = -75.0
        while db <= 3 {
            let f = IECScale.fraction(db: db)
            XCTAssertGreaterThanOrEqual(f, previous, "falls at \(db) dBFS")
            XCTAssertLessThan(f - previous, 0.0035, "jumps at \(db) dBFS")
            previous = f
            db += 0.1
        }
    }
}
