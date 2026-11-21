// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class CurveDataTests: XCTestCase {
    func testColumnsKeepEveryPeak() {
        var s = [Float](repeating: 0.01, count: 1000)
        s[503] = 0.9
        s[777] = -0.7
        let data = CurveData(samples: s, sampleRate: 48000)
        let c = data.columns(from: 0, to: 1000, width: 10)
        XCTAssertEqual(c.maximums.max(), 0.9)
        XCTAssertEqual(c.minimums.min(), -0.7)
        XCTAssertEqual(c.maximums[5], 0.9)
        XCTAssertEqual(c.minimums[7], -0.7)
    }

    func testZoomedInColumnsFollowTheSamples() {
        let data = CurveData(samples: [0, 1, 0, -1], sampleRate: 48000)
        let c = data.columns(from: 0, to: 4, width: 8)
        XCTAssertEqual(c.maximums.count, 8)
        XCTAssertEqual(c.maximums[2], 1)
        XCTAssertEqual(c.minimums[6], -1)
    }

    func testDecibelScale() {
        let scale = CurveScale.decibels(floorDB: -90)
        XCTAssertEqual(scale.height(of: 1, reference: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(scale.height(of: -0.001, reference: 1), -(30.0 / 90.0), accuracy: 1e-6)
        XCTAssertEqual(scale.height(of: 0, reference: 1), 0)
        XCTAssertEqual(scale.height(of: 1e-9, reference: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(CurveScale.linear.height(of: 0.5, reference: 1), 0.5, accuracy: 1e-9)
    }
}

final class SpectrumTests: XCTestCase {
    /// A pulse has a flat spectrum, whatever its position, at the level of its height.
    func testPulseIsFlat() {
        var s = [Float](repeating: 0, count: 512)
        s[0] = 1
        let spectrum = Spectrum(samples: s, sampleRate: 48000)
        XCTAssertFalse(spectrum.points.isEmpty)
        for p in spectrum.points { XCTAssertEqual(p.decibels, 0, accuracy: 0.1) }
    }

    /// A gain of one half is 6 dB lower.
    func testHalfGain() {
        var s = [Float](repeating: 0, count: 512)
        s[3] = 0.5
        let spectrum = Spectrum(samples: s, sampleRate: 48000)
        XCTAssertEqual(spectrum.peakDecibels, -6.02, accuracy: 0.1)
    }

    /// A sine at 1 kHz makes the spectrum peak around 1 kHz.
    func testSinePeak() {
        let rate = 48000.0
        let s = (0..<4800).map { Float(sin(2 * Double.pi * 1000 * Double($0) / rate)) }
        let spectrum = Spectrum(samples: s, sampleRate: rate, fractionOfOctave: 24)
        let top = spectrum.points.max { $0.decibels < $1.decibels }!
        XCTAssertEqual(top.frequency, 1000, accuracy: 60)
    }
}

