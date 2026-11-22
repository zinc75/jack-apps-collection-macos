// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ImpulseZoneTests: XCTestCase {
    func testAZoneInsideTheFileStaysAsItIs() {
        let z = ImpulseZone.clamped(start: 60, end: 360, total: 512)
        XCTAssertEqual(z.start, 60)
        XCTAssertEqual(z.end, 360)
    }

    /// A typed value outside the file, or past the other end, is brought back: the text of the field must then show the value that was kept.
    func testValuesAreBroughtBack() {
        XCTAssertEqual(ImpulseZone.clamped(start: -5, end: 100, total: 512).start, 0)
        XCTAssertEqual(ImpulseZone.clamped(start: 10, end: 9999, total: 512).end, 511)
        let crossed = ImpulseZone.clamped(start: 300, end: 200, total: 512)
        XCTAssertEqual(crossed.start, 300)
        XCTAssertEqual(crossed.end, 301)
        let late = ImpulseZone.clamped(start: 600, end: 700, total: 512)
        XCTAssertEqual(late.start, 510)
        XCTAssertEqual(late.end, 511)
    }

    func testTinyFiles() {
        XCTAssertEqual(ImpulseZone.clamped(start: 0, end: 5, total: 1).end, 0)
        XCTAssertEqual(ImpulseZone.clamped(start: 3, end: 9, total: 2).start, 0)
    }

    func testLengthIsZeroToTheEndOfTheFile() {
        XCTAssertEqual(ImpulseZone.length(start: 60, end: 511, total: 512), 0)
        XCTAssertEqual(ImpulseZone.length(start: 60, end: 360, total: 512), 300)
        XCTAssertEqual(ImpulseZone.length(start: 60, end: 61, total: 512), 1)
    }
}
