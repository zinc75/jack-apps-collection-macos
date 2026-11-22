// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

/// A small generator that gives the same numbers every time.
struct Lcg {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func float() -> Float { Float(next() * 2 - 1) }
}

final class PeakPyramidTests: XCTestCase {
    private func noise(_ n: Int, seed: UInt64 = 1) -> [Float] {
        var g = Lcg(state: seed)
        return (0..<n).map { _ in g.float() }
    }

    func testDirectColumnsAreExact() {
        let data = noise(5000)
        let p = PeakPyramid(samples: data)
        let e = p.envelope(from: 1000, to: 2000, columns: 100)   // 10 samples per column: read from the samples
        for c in 0..<100 {
            let a = 1000 + c * 10, b = 1000 + (c + 1) * 10
            let slice = data[a...b]
            XCTAssertEqual(e.lo[c], slice.min()!, "column \(c)")
            XCTAssertEqual(e.hi[c], slice.max()!, "column \(c)")
        }
        XCTAssertEqual(e.valid, 0..<100)
    }

    func testPyramidColumnsHoldWhatTheyCover() {
        // Far from the direct limit the extremes come from blocks: never narrower than the samples of the column, and
        // never wider than the samples of the column widened by a few blocks.
        let data = noise(200_000, seed: 7)
        let p = PeakPyramid(samples: data)
        for (x0, x1, columns) in [(0.0, 200_000.0, 1000), (5000.0, 105_000.0, 700), (123_456.0, 190_000.0, 333)] {
            let e = p.envelope(from: x0, to: x1, columns: columns)
            let spc = (x1 - x0) / Double(columns)
            for c in 0..<columns {
                let a = Int((x0 + Double(c) * spc).rounded(.down)), b = min(data.count - 1, Int((x0 + Double(c + 1) * spc).rounded(.down)))
                let exact = data[a...b]
                XCTAssertLessThanOrEqual(e.lo[c], exact.min()!)
                XCTAssertGreaterThanOrEqual(e.hi[c], exact.max()!)
                let wide = data[max(0, a - 2000)...min(data.count - 1, b + 2000)]
                XCTAssertGreaterThanOrEqual(e.lo[c], wide.min()!)
                XCTAssertLessThanOrEqual(e.hi[c], wide.max()!)
            }
        }
    }

    func testWholeSignalKeepsTheGlobalExtremes() {
        let data = noise(1_000_003, seed: 3)
        let p = PeakPyramid(samples: data)
        for columns in [1, 7, 500, 3000] {
            let e = p.envelope(from: 0, to: Double(data.count), columns: columns)
            XCTAssertEqual(e.lo.min()!, data.min()!)
            XCTAssertEqual(e.hi.max()!, data.max()!)
        }
    }

    func testAnIsolatedPeakIsNeverLost() {
        // The property that matters on a plot: a single sample far above the rest shows at every zoom.
        var data = [Float](repeating: 0, count: 5_000_000)
        data[3_141_592] = 1
        let p = PeakPyramid(samples: data)
        for range in [5_000_000.0, 1_000_000, 100_000, 10_000, 1000, 100] {
            let x0 = max(0, 3_141_592 - range / 3)
            let e = p.envelope(from: x0, to: x0 + range, columns: 2400)
            XCTAssertEqual(e.hi.max(), 1, "range \(range)")
            XCTAssertEqual(e.lo.min(), 0)
            let column = e.hi.firstIndex(of: 1)!
            let expected = Int((3_141_592 - x0) / range * 2400)
            XCTAssertLessThanOrEqual(abs(column - expected), 1, "range \(range)")
        }
    }

    func testWindowOutsideTheSignal() {
        let p = PeakPyramid(samples: noise(1000))
        let before = p.envelope(from: -500, to: 500, columns: 10)
        // Column 4 ends at the first sample, which it includes: it is the first that holds data.
        XCTAssertEqual(before.valid, 4..<10)
        XCTAssertEqual(before.lo[0], 0); XCTAssertEqual(before.hi[3], 0)
        let after = p.envelope(from: 500, to: 1500, columns: 10)
        XCTAssertEqual(after.valid, 0..<5)
        let away = p.envelope(from: 5000, to: 6000, columns: 10)
        XCTAssertEqual(away.valid, 0..<0)
        let across = p.envelope(from: -10_000, to: 11_000, columns: 21)
        XCTAssertEqual(across.valid, 9..<11)
    }

    func testDegenerateInputs() {
        let empty = PeakPyramid(samples: [])
        XCTAssertEqual(empty.envelope(from: 0, to: 10, columns: 4).valid, 0..<0)
        let one = PeakPyramid(samples: [0.5])
        let e = one.envelope(from: -2, to: 2, columns: 4)
        XCTAssertEqual(e.hi.max(), 0.5)
        XCTAssertEqual(one.envelope(from: 10, to: 10, columns: 4).valid, 0..<0)
        XCTAssertEqual(one.envelope(from: 0, to: 1, columns: 0).columns, 0)
        XCTAssertEqual(one.envelope(from: .nan, to: 1, columns: 3).valid, 0..<0)
        XCTAssertNil(one.extremes(in: 3..<9))
        XCTAssertEqual(PeakPyramid(samples: noise(100)).extremes(in: -5..<1000)?.max, noise(100).max())
    }

    func testMagnitude() {
        var e = Envelope(columns: 3)
        e.lo = [-0.5, 0.2, -0.9]; e.hi = [0.25, 0.7, -0.3]
        let m = e.magnitude()
        XCTAssertEqual(m.hi, [0.5, 0.7, 0.9])
        XCTAssertEqual(m.lo, [0, 0.2, 0.3])
    }

    func testReuseOfTheBuffers() {
        let p = PeakPyramid(samples: noise(10_000))
        var e = Envelope()
        p.envelope(from: 0, to: 10_000, columns: 50, into: &e)
        XCTAssertEqual(e.columns, 50)
        p.envelope(from: 0, to: 10_000, columns: 80, into: &e)
        XCTAssertEqual(e.columns, 80)
        XCTAssertEqual(e, p.envelope(from: 0, to: 10_000, columns: 80))
    }
}
