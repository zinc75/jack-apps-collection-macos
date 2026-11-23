// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class EngineSamplesTests: XCTestCase {
    private let file: [Float] = [1, 2, 3, 4, 5, 6]

    func testWithoutAnythingItIsTheFile() {
        XCTAssertEqual(EngineSamples.make(file, offset: 0, length: 0, gain: 1, delay: 0), file)
    }

    func testTheStartAndTheLengthCutTheFile() {
        XCTAssertEqual(EngineSamples.make(file, offset: 2, length: 3, gain: 1, delay: 0), [3, 4, 5])
        // A length of 0 reads to the end; a length that goes past the end stops there.
        XCTAssertEqual(EngineSamples.make(file, offset: 4, length: 0, gain: 1, delay: 0), [5, 6])
        XCTAssertEqual(EngineSamples.make(file, offset: 4, length: 10, gain: 1, delay: 0), [5, 6])
        XCTAssertEqual(EngineSamples.make(file, offset: 9, length: 0, gain: 1, delay: 0), [])
    }

    func testTheGainMultipliesAndTheDelayPutsSilenceBefore() {
        XCTAssertEqual(EngineSamples.make(file, offset: 1, length: 2, gain: 0.5, delay: 3), [0, 0, 0, 1, 1.5])
        XCTAssertEqual(EngineSamples.make(file, offset: 0, length: 2, gain: .infinity, delay: 0), [0, 0])
    }
}
