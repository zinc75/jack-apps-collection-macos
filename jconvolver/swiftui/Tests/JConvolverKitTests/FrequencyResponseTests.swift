// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class FrequencyResponseTests: XCTestCase {
    private func pulse(at index: Int, height: Float = 1, count: Int = 512) -> [Float] {
        var s = [Float](repeating: 0, count: count)
        s[index] = height
        return s
    }

    /// A pulse has a flat magnitude at the level of its height, whatever its position.
    func testPulseIsFlat() {
        let r = FrequencyResponse(samples: pulse(at: 0), sampleRate: 48000)
        XCTAssertFalse(r.isEmpty)
        for m in r.magnitudes { XCTAssertEqual(m, 1, accuracy: 1e-9) }
        let half = FrequencyResponse(samples: pulse(at: 3, height: 0.5), sampleRate: 48000)
        for m in half.magnitudes { XCTAssertEqual(m, 0.5, accuracy: 1e-9) }
    }

    /// A pure delay has a group delay that is that delay at every frequency: 48 samples at 48 kHz are 1 ms.
    func testPureDelay() {
        let r = FrequencyResponse(samples: pulse(at: 48), sampleRate: 48000)
        for g in r.groupDelays { XCTAssertEqual(g, 1, accuracy: 1e-6) }
    }

    /// The delay is counted from the first frame of the range the engine reads.
    func testDelayIsCountedFromTheRange() {
        let r = FrequencyResponse(samples: pulse(at: 148, count: 1000), range: 100..<400, sampleRate: 48000)
        for g in r.groupDelays { XCTAssertEqual(g, 1, accuracy: 1e-6) }
        XCTAssertTrue(FrequencyResponse(samples: pulse(at: 148, count: 1000), range: 10..<11, sampleRate: 48000).isEmpty)
    }

    /// A pulse delayed by d samples has the phase −2π f d / fs: a quarter turn at a quarter of fs for a delay of one sample.
    func testPhaseOfADelay() {
        let r = FrequencyResponse(samples: pulse(at: 1), sampleRate: 48000)
        let k = (r.frequencies.count - 1) / 2   // half the Nyquist frequency: fs / 4
        XCTAssertEqual(r.frequencies[k], 12000, accuracy: 1e-6)
        XCTAssertEqual(r.phases[k], -90, accuracy: 1e-6)
    }

    /// Two pulses (a direct sound and an echo): the group delay is not the one of either, but it follows the exact formula, which the
    /// slope of the phase gives too where the phase can be unwrapped. Here the response of the pair has a known value at DC:
    /// (0·1 + 24·0.5) / (1 + 0.5) samples = 8 samples = 1/6 ms.
    func testGroupDelayOfAnEcho() {
        var s = [Float](repeating: 0, count: 512)
        s[0] = 1
        s[24] = 0.5
        let r = FrequencyResponse(samples: s, sampleRate: 48000)
        XCTAssertEqual(r.groupDelays[0], 8.0 / 48.0, accuracy: 1e-6)
    }

    /// A silent block has nothing to say about the group delay.
    func testSilence() {
        let r = FrequencyResponse(samples: [Float](repeating: 0, count: 512), sampleRate: 48000)
        XCTAssertTrue(r.groupDelays.allSatisfy { $0.isNaN })
    }
}
