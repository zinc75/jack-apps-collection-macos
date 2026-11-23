// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class SpectrumComparisonTests: XCTestCase {
    private func response(_ samples: [Float], rate: Double = 48000) -> FrequencyResponse { FrequencyResponse(samples: samples, sampleRate: rate) }

    func testTheSameResponseIsZeroDecibelsAway() throws {
        let samples = (0..<1000).map { Float(sin(Double($0) * 0.3) * exp(-Double($0) / 200)) }
        let a = response(samples)
        let deviation = try XCTUnwrap(SpectrumComparison.maxDeviation(a, a))
        XCTAssertEqual(deviation.decibels, 0, accuracy: 1e-9)
    }

    func testAGainIsFoundAsItIs() throws {
        let samples = (0..<1000).map { Float(sin(Double($0) * 0.3) * exp(-Double($0) / 200)) }
        let louder = samples.map { $0 * 2 }
        let deviation = try XCTUnwrap(SpectrumComparison.maxDeviation(response(louder), response(samples)))
        // A factor of two is 6.02 dB over the whole band.
        XCTAssertEqual(deviation.decibels, 6.0206, accuracy: 0.01)
    }

    func testNothingToCompareGivesNothing() {
        XCTAssertNil(SpectrumComparison.maxDeviation(response([]), response([1, 0, 0, 0])))
    }

    func testTheDifferenceOfTheSameResponseIsZeroAndOfAGainIsTheMagnitudeOfTheQuieterOne() {
        let samples = (0..<1000).map { Float(sin(Double($0) * 0.3) * exp(-Double($0) / 200)) }
        let a = response(samples)
        let same = SpectrumComparison.difference(a, a)
        XCTAssertFalse(same.frequencies.isEmpty)
        XCTAssertEqual(same.magnitudes.max() ?? 1, 0, accuracy: 1e-12)
        // 2x against 1x, and 3x against 2x, are each a distance of one times the response.
        let first = SpectrumComparison.difference(response(samples.map { $0 * 2 }), a)
        let second = SpectrumComparison.difference(response(samples.map { $0 * 3 }), response(samples.map { $0 * 2 }))
        XCTAssertEqual(first.magnitudes.count, second.magnitudes.count)
        for (x, y) in zip(first.magnitudes, second.magnitudes) { XCTAssertEqual(x, y, accuracy: max(x, y) * 1e-4 + 1e-12) }
        XCTAssertGreaterThan(first.magnitudes.max() ?? 0, 0)
    }

    func testTwoRatesAreComparedOnTheSameBands() {
        // The same smooth response at two rates has bins that are not the same: the bands are.
        let slow = (0..<1000).map { Float(exp(-Double($0) / 100)) }
        let fast = (0..<1088).map { Float(exp(-Double($0) / 108.8) / 1.088) }
        let difference = SpectrumComparison.difference(FrequencyResponse(samples: fast, sampleRate: 48000), FrequencyResponse(samples: slow, sampleRate: 44100))
        XCTAssertFalse(difference.frequencies.isEmpty)
        // A decaying exponential has the same spectrum at both rates once its gain is compensated.
        let reference = FrequencyResponse(samples: slow, sampleRate: 44100)
        XCTAssertLessThan(difference.magnitudes.max() ?? 1, reference.magnitudes.max()! * 0.05)
    }
}
