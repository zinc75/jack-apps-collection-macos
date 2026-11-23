// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class NumberFilterTests: XCTestCase {
    func testOneNumberSeveralAndARange() {
        XCTAssertEqual(NumberFilter.numbers("3"), [3])
        XCTAssertEqual(NumberFilter.numbers("1,3"), [1, 3])
        XCTAssertEqual(NumberFilter.numbers("2-4"), [2, 3, 4])
        XCTAssertEqual(NumberFilter.numbers("1 3-5"), [1, 3, 4, 5])
    }

    func testNothingUnderstoodMeansNoFilter() {
        XCTAssertNil(NumberFilter.numbers(""))
        XCTAssertNil(NumberFilter.numbers("a"))
        XCTAssertNil(NumberFilter.numbers("4-2"))
        XCTAssertNil(NumberFilter.numbers("-"))
    }
}
