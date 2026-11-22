// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class SmoothingTests: XCTestCase {
    /// The regular bins of a transform, from 5 Hz to 24 kHz.
    private func bins() -> [Double] { (1...4800).map { Double($0) * 5 } }

    private func magnitude(_ values: [Double]) -> PlotCurve { PlotCurve(name: "m", x: bins(), y: values, isMagnitude: true) }

    func testAConstantSpectrumStaysConstant() {
        let c = magnitude([Double](repeating: 0.5, count: 4800))
        for s in OctaveSmoothing.allCases { for v in c.smoothed(s).y { XCTAssertEqual(v, 0.5, accuracy: 1e-12) } }
    }

    func testThePowerIsAveragedNotTheMagnitude() {
        // Two bins in the band, 1 and 3: the mean power is 5, so the smoothed magnitude is √5, not 2.
        let c = PlotCurve(name: "m", x: [100, 101, 5000], y: [1, 3, 1], isMagnitude: true)
        let out = c.smoothed(.third).y
        XCTAssertEqual(out[0], 5.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(out[1], 5.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(out[2], 1, accuracy: 1e-12, "alone in its band")
    }

    func testAWiderBandSmoothsMore() {
        var g = Lcg(state: 5)
        let c = magnitude(bins().map { _ in abs(g.next()) + 0.1 })
        func spread(_ s: OctaveSmoothing) -> Double {
            // The variation from point to point, above 1 kHz where the bands hold many bins.
            let xs = bins()
            let y = c.smoothed(s).y.enumerated().filter { xs[$0.offset] > 1000 }.map(\.element)
            return zip(y, y.dropFirst()).map { abs($0 - $1) }.reduce(0, +) / Double(y.count)
        }
        let order: [OctaveSmoothing] = [.twentyFourth, .twelfth, .sixth, .third, .half, .octave]
        let spreads = order.map(spread)
        for (a, b) in zip(spreads, spreads.dropFirst()) { XCTAssertGreaterThan(a, b, "\(a) then \(b)") }
        XCTAssertGreaterThan(spread(.twentyFourth), 0)
    }

    func testASpikeSpreadsOverTheBandAndKeepsItsEnergy() {
        var y = [Double](repeating: 0, count: 4800)
        y[999] = 1                       // 5 kHz, one bin
        let out = magnitude(y).smoothed(.third)
        let xs = bins()
        let inBand = out.y.enumerated().filter { $0.element > 0 }.map { xs[$0.offset] }
        XCTAssertGreaterThan(inBand.count, 50)
        // Every point that sees the spike is within a sixth of an octave on each side of it.
        let ratio = pow(2, 1.0 / 6)
        XCTAssertGreaterThanOrEqual(inBand.min()! , 5000 / ratio * 0.999)
        XCTAssertLessThanOrEqual(inBand.max()!, 5000 * ratio * 1.001)
        XCTAssertLessThan(out.y.max()!, 1, "lower than the spike: its energy is shared")
    }

    func testTheDcBinAndNonFiniteValuesAreLeftAlone() {
        let c = PlotCurve(name: "m", x: [0, 100, 101, 102], y: [7, 1, .nan, 3], isMagnitude: true)
        let out = c.smoothed(.octave).y
        XCTAssertEqual(out[0], 7, "no smoothing at 0 Hz")
        XCTAssertTrue(out[2].isNaN)
        XCTAssertEqual(out[1], 5.0.squareRoot(), accuracy: 1e-12, "the NaN is left out of the mean")
    }

    func testOnlyMagnitudesAreSmoothedAndNoneIsNoChange() {
        let phase = PlotCurve(name: "p", x: bins(), y: bins().map { $0 / 100 }, phase: .degrees)
        XCTAssertEqual(phase.smoothed(.third).y, phase.y, "not a magnitude")
        let m = magnitude(bins().map { 1 / $0 })
        XCTAssertEqual(m.smoothed(.none).y, m.y)
        XCTAssertEqual(PlotCurve(name: "m", x: [1], y: [1], isMagnitude: true).smoothed(.third).y, [1])
    }

    func testTitles() {
        XCTAssertEqual(OctaveSmoothing.third.title, "1/3 octave")
        XCTAssertEqual(OctaveSmoothing.octave.title, "1 octave")
        XCTAssertEqual(OctaveSmoothing.twentyFourth.title, "1/24 octave")
        XCTAssertEqual(OctaveSmoothing.allCases.count, 7)
    }

    func testTheRawCurveBehindCannotBeReadOff() {
        var raw = magnitude([1, 2, 3].map { Double($0) } + [Double](repeating: 1, count: 4797))
        raw.isReference = true
        let smooth = magnitude([Double](repeating: 9, count: 4800))
        let content = CurveContent(curves: [smooth, raw], yScale: .linear, xUnitText: "Hz", yUnitText: "")
        let t = PlotTransform(viewport: PlotViewport.curves([smooth, raw]), rect: CGRect(x: 0, y: 0, width: 800, height: 400))
        let probe = content.probe(at: CGPoint(x: t.x(1000), y: t.y(1)), t)
        XCTAssertEqual(probe.trace, 0, "the reference is not read, the smoothed curve is")
    }
}
