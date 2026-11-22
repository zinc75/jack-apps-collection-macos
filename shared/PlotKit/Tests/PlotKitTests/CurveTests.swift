// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class CurveTests: XCTestCase {
    private func curve(_ xs: [Double]) -> PlotCurve { PlotCurve(name: "c", x: xs, y: xs.map { $0 * 2 }) }

    func testSearchInAnIncreasingAbscissa() {
        let c = curve([0, 10, 20, 40, 80])
        XCTAssertEqual(c.lowerBound(-5), 0)
        XCTAssertEqual(c.lowerBound(10), 1, "the first that is not below")
        XCTAssertEqual(c.lowerBound(11), 2)
        XCTAssertEqual(c.lowerBound(1000), 5, "the count when there is none")
        XCTAssertEqual(c.nearest(31), 3)
        XCTAssertEqual(c.nearest(29), 2)
        XCTAssertEqual(c.nearest(-100), 0)
        XCTAssertEqual(c.nearest(1000), 4)
        XCTAssertNil(PlotCurve(name: "e", x: [], y: []).nearest(1))
    }

    func testTheShorterOfTheTwoArraysCounts() {
        let c = PlotCurve(name: "c", x: [1, 2, 3, 4], y: [1, 2])
        XCTAssertEqual(c.count, 2)
    }

    func testViewportOfCurvesLinear() {
        let c = PlotCurve(name: "m", x: [0, 100, 200, 400], y: [1, 3, 2, 0])
        let v = PlotViewport.curves([c])
        XCTAssertEqual(v.x.range, 0...400)
        XCTAssertEqual(v.x.scale, .linear)
        XCTAssertLessThan(v.y.range.lowerBound, 0)
        XCTAssertGreaterThan(v.y.range.upperBound, 3)
        XCTAssertTrue(v.isFitted)
    }

    func testViewportOfCurvesLogarithmicSkipsZero() {
        // A spectrum has a bin at 0 Hz, which a logarithmic axis cannot show.
        let c = PlotCurve(name: "m", x: [0, 50, 500, 20_000], y: [1, 1, 0.5, 0.1])
        let v = PlotViewport.curves([c], xScale: .logarithmic)
        XCTAssertEqual(v.x.range, 50...20_000)
        XCTAssertEqual(v.x.scale, .logarithmic)
        XCTAssertEqual(v.x.fraction(of: sqrt(50 * 20_000.0)), 0.5, accuracy: 1e-9)
    }

    func testViewportOfCurvesInDecibels() {
        let c = PlotCurve(name: "m", x: [100, 200, 300], y: [1, 0.1, 0.0])   // 0 dB, −20 dB, and zero: the floor
        let v = PlotViewport.curves([c], yScale: .decibels(floor: -90))
        XCTAssertGreaterThanOrEqual(v.y.range.lowerBound, -91)
        XCTAssertGreaterThan(v.y.range.upperBound, 0)
    }

    func testViewportOfNothingIsUsable() {
        let v = PlotViewport.curves([])
        XCTAssertGreaterThan(v.x.range.upperBound, v.x.range.lowerBound)
        XCTAssertGreaterThan(v.y.range.upperBound, v.y.range.lowerBound)
    }

    func testAutoscaleOfCurvesUsesTheVisiblePart() {
        let xs = (0..<1000).map(Double.init)
        let c = PlotCurve(name: "c", x: xs, y: xs.map { $0 < 500 ? 1 : 10 })
        var v = PlotViewport.curves([c])
        v.x = v.x.showing(0...400)
        let content = CurveContent(curves: [c], yScale: .linear, xUnitText: "", yUnitText: "")
        let scaled = content.autoscale(v)
        XCTAssertLessThan(scaled.y.range.upperBound, 2, "the 10s are outside the visible part")
        XCTAssertGreaterThan(scaled.y.range.upperBound, 1)
    }

    func testProbeSnapsToTheNearestPointAndReadsIt() {
        let c = PlotCurve(name: "magnitude", x: [100, 200, 400, 800], y: [1, 0.5, 0.25, 0.125])
        let v = PlotViewport.curves([c])
        let t = PlotTransform(viewport: v, rect: CGRect(x: 0, y: 0, width: 800, height: 400))
        let content = CurveContent(curves: [c], yScale: .decibels(floor: -90), xUnitText: "Hz", yUnitText: "")
        let near = CGPoint(x: t.x(405), y: 200)
        let probe = content.probe(at: near, t)
        XCTAssertTrue(probe.onData)
        XCTAssertEqual(probe.xFlag, "400 Hz")
        XCTAssertEqual(probe.yFlag, "−12.0 dB")
        XCTAssertEqual(probe.card.first, "magnitude")
        // Far from any point, the crosshair is free.
        let farContent = CurveContent(curves: [PlotCurve(name: "a", x: [100, 800], y: [1, 1])], yScale: .linear, xUnitText: "Hz", yUnitText: "")
        XCTAssertFalse(farContent.probe(at: CGPoint(x: 400, y: 200), t).onData)
    }

    func testMeasureReadoutGivesTheRatioInOctaves() {
        let content = CurveContent(curves: [], yScale: .decibels(floor: -90), xUnitText: "Hz", yUnitText: "")
        let lines = content.measureReadout(PlotSegment(x0: 250, y0: -3, x1: 500, y1: -9))
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].contains("×2"), lines[1])
        XCTAssertTrue(lines[1].contains("1 oct"), lines[1])
        XCTAssertEqual(lines[2], "Δ = −6.0 dB")
    }
}

final class VisibleRangeTests: XCTestCase {
    func testTheFirstViewCanBeAPartOfTheData() {
        // A spectrum from 0.17 Hz: the audio band is what one looks at first, the rest is still there.
        let xs = (1...4000).map { Double($0) * 6 }
        let c = PlotCurve(name: "m", x: xs, y: xs.map { 1 / $0 })
        let v = PlotViewport.curves([c], xScale: .logarithmic, visibleX: 20...20_000)
        XCTAssertEqual(v.x.range, 20...20_000)
        XCTAssertEqual(v.x.bounds, 6...24_000)
        XCTAssertFalse(v.isFitted)
        XCTAssertEqual(v.x.fitted().range, 6...24_000, "everything is one reset away")
    }
}

final class UnwrapTests: XCTestCase {
    private func wrap(_ v: Double, _ period: Double) -> Double { v - period * ((v + period / 2) / period).rounded(.down) }

    func testALinearPhaseComesBackFromItsWrappedValues() {
        // A delay: a phase that falls in a straight line, seen between −180° and +180°.
        let xs = (0..<200).map { Double($0) * 50 }
        let truth = xs.map { -0.9 * $0 }
        let wrapped = truth.map { wrap($0, 360) }
        XCTAssertNotEqual(wrapped.min(), wrapped.max())
        XCTAssertLessThanOrEqual(wrapped.max()!, 180); XCTAssertGreaterThanOrEqual(wrapped.min()!, -180)
        let curve = PlotCurve(name: "p", x: xs, y: wrapped, phase: .degrees)
        let un = curve.unwrapped().y
        // The unwrapped phase is the true one up to a whole number of turns of its first value.
        for (u, t) in zip(un, truth) { XCTAssertEqual(u - t, un[0] - truth[0], accuracy: 1e-9) }
        XCTAssertLessThan(un.last!, -8000)
    }

    func testRadians() {
        let truth = (0..<100).map { 0.5 * Double($0) }
        let wrapped = truth.map { wrap($0, 2 * .pi) }
        let un = PlotCurve(name: "p", x: Array(0..<100).map(Double.init), y: wrapped, phase: .radians).unwrapped().y
        for (u, t) in zip(un, truth) { XCTAssertEqual(u, t, accuracy: 1e-9) }
    }

    func testACurveThatIsNotAPhaseIsLeftAlone() {
        let c = PlotCurve(name: "m", x: [1, 2, 3], y: [170, -170, 170])
        XCTAssertEqual(c.unwrapped().y, [170, -170, 170])
    }

    func testNonFiniteValuesAreSkippedAndTheUnwrappingGoesOn() {
        let c = PlotCurve(name: "p", x: [1, 2, 3, 4, 5], y: [170, .nan, -170, -150, .infinity], phase: .degrees)
        let u = c.unwrapped().y
        XCTAssertEqual(u[0], 170)
        XCTAssertTrue(u[1].isNaN)
        XCTAssertEqual(u[2], 190, accuracy: 1e-9, "−170° after 170° is a step of +20°, not −340°")
        XCTAssertEqual(u[3], 210, accuracy: 1e-9)
        XCTAssertTrue(u[4].isInfinite)
    }

    func testUnwrappingKeepsTheSmallSteps() {
        let y = [0.0, 100, 190, 280, 370, 460]   // steps of 90°, already continuous
        let u = PlotCurve(name: "p", x: [0, 1, 2, 3, 4, 5], y: y, phase: .degrees).unwrapped().y
        XCTAssertEqual(u, y)
    }

    func testTheViewportOfAnUnwrappedPhaseSpansItsTurns() {
        let xs = (0..<100).map { Double($0) }
        let wrapped = xs.map { wrap(-30 * $0, 360) }
        let c = PlotCurve(name: "p", x: xs, y: wrapped, phase: .degrees)
        XCTAssertLessThan(PlotViewport.curves([c]).y.range.upperBound - PlotViewport.curves([c]).y.range.lowerBound, 400)
        let v = PlotViewport.curves([c.unwrapped()])
        XCTAssertGreaterThan(v.y.range.upperBound - v.y.range.lowerBound, 2900)
    }
}

final class LargeValueTextTests: XCTestCase {
    func testALargeValueIsNotInScientificNotation() {
        let content = CurveContent(curves: [], yScale: .linear, xUnitText: "Hz", yUnitText: "°")
        let t = PlotTransform(viewport: PlotViewport(x: AxisState(bounds: 0...10), y: AxisState(bounds: -900_000...0)), rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        let probe = content.probe(at: CGPoint(x: 50, y: 50), t)   // no curve: a free crosshair
        XCTAssertFalse(probe.yFlag.contains("e+"), probe.yFlag)
        XCTAssertTrue(probe.yFlag.hasPrefix("−"), probe.yFlag)
        XCTAssertTrue(probe.yFlag.hasSuffix(" °"), probe.yFlag)
    }
}

final class RemoveDelayTests: XCTestCase {
    private func wrap(_ v: Double, _ period: Double) -> Double { v - period * ((v + period / 2) / period).rounded(.down) }
    private let delay = 0.0125   // seconds
    private func xs() -> [Double] { (1..<400).map { Double($0) * 20 } }   // a step under 1/(2τ) = 40 Hz: finer than half a turn per point

    private func delayed(_ unit: PhaseUnit = .degrees, host: Double? = nil, extra: ((Double) -> Double)? = nil) -> PlotCurve {
        let p = unit.period
        // H(f) = e^(−j 2π f τ): a phase that falls by one turn per 1/τ hertz.
        let y = xs().map { wrap(-p * $0 * delay + (extra?($0) ?? 0), p) }
        return PlotCurve(name: "p", x: xs(), y: y, phase: unit, delay: host)
    }

    func testTheDelayIsEstimatedFromTheFit() {
        let c = delayed()
        XCTAssertEqual(c.estimatedDelay()!, delay, accuracy: 1e-9)
        XCTAssertEqual(delayed(.radians).estimatedDelay()!, delay, accuracy: 1e-9)
        XCTAssertNil(PlotCurve(name: "m", x: [1, 2], y: [1, 2]).estimatedDelay(), "not a phase")
        XCTAssertNil(PlotCurve(name: "p", x: [5], y: [1], phase: .degrees).estimatedDelay(), "one point")
    }

    func testRemovingTheDelayFlattensAPureDelayWhetherUnwrappedOrNot() {
        let c = delayed()
        for v in c.processed(unwrap: false, removeDelay: true).y { XCTAssertEqual(v, 0, accuracy: 1e-6) }
        let un = c.processed(unwrap: true, removeDelay: true).y
        for v in un { XCTAssertEqual(v, un[0], accuracy: 1e-6, "flat, and continuous (no turns left)") }
    }

    func testWhatIsLeftIsThePhaseOfTheSystem() {
        // A delay and a bump of the system's own phase: removing the delay leaves the bump.
        let bump = { (f: Double) in 40 * sin(f / 4000) }
        let c = delayed(extra: bump)
        let rest = c.processed(unwrap: true, removeDelay: true)
        let un = rest.y
        // Before, the phase falls over thousands of degrees; after, it only moves about as much as the system's own bump (80° wide).
        XCTAssertGreaterThan(abs(c.processed(unwrap: true, removeDelay: false).y.last! - c.processed(unwrap: true, removeDelay: false).y.first!), 1000)
        XCTAssertLessThan(un.max()! - un.min()!, 110)
    }

    func testTheHostDelayWinsOverTheFit() {
        let c = delayed(host: 0.0125)
        for v in c.processed(unwrap: false, removeDelay: true).y { XCTAssertEqual(v, 0, accuracy: 1e-6) }
        let wrong = delayed(host: 0.02)   // a delay that is not the one of the curve: the straight line left is not flat
        let y = wrong.processed(unwrap: true, removeDelay: true).y
        XCTAssertGreaterThan(abs(y.last! - y.first!), 1000)
    }

    func testNothingToDoLeavesTheCurve() {
        let c = delayed()
        XCTAssertEqual(c.processed(unwrap: false, removeDelay: false).y, c.y)
        let m = PlotCurve(name: "m", x: [1, 2, 3], y: [170, -170, 170], delay: 1)
        XCTAssertEqual(m.processed(unwrap: true, removeDelay: true).y, m.y, "not a phase")
    }

    func testRadiansUseTheirPeriod() {
        let c = delayed(.radians, host: delay)
        for v in c.processed(unwrap: false, removeDelay: true).y { XCTAssertEqual(v, 0, accuracy: 1e-9) }
    }
}

@MainActor
final class DelayValueTests: XCTestCase {
    func testTheControllerCarriesTheDelaysTheInspectorShows() {
        let c = PlotController()
        c.phaseDelays = [.init(name: "Ch. 1", seconds: 0.0125, isEstimated: false), .init(name: "Ch. 2", seconds: 0.0131, isEstimated: true)]
        XCTAssertEqual(TickLabels.engineering(c.phaseDelays[0].seconds, unit: "s"), "12.5 ms")
        XCTAssertTrue(c.phaseDelays[1].isEstimated)
        XCTAssertEqual(PlotLabels().delayFitted, "fitted")
    }
}

final class GroupDelayTests: XCTestCase {
    private func wrap(_ v: Double, _ period: Double) -> Double { v - period * ((v + period / 2) / period).rounded(.down) }

    func testAPureDelayHasAConstantGroupDelay() {
        let delay = 0.0125   // 12.5 ms
        // Irregular abscissas: the derivative does not assume a step.
        var x = 0.0, xs: [Double] = []
        for i in 0..<300 { x += 8 + Double(i % 7); xs.append(x) }
        for unit in [PhaseUnit.degrees, .radians] {
            let p = unit.period
            let c = PlotCurve(name: "p", x: xs, y: xs.map { wrap(-p * $0 * delay, p) }, phase: unit)
            let g = c.groupDelay()
            XCTAssertTrue(g.isGroupDelay)
            XCTAssertNil(g.phase)
            for v in g.y { XCTAssertEqual(v, 12.5, accuracy: 1e-6, "in milliseconds") }
        }
    }

    func testTheGroupDelayFollowsTheSlope() {
        // The phase falls twice as fast above 5 kHz: twice the delay there.
        let xs = (1...400).map { Double($0) * 20 }
        let phase = xs.map { f -> Double in f < 5000 ? -360 * f * 0.002 : -360 * (5000 * 0.002 + (f - 5000) * 0.004) }
        let g = PlotCurve(name: "p", x: xs, y: phase.map { wrap($0, 360) }, phase: .degrees).groupDelay().y
        XCTAssertEqual(g[100], 2, accuracy: 1e-6)    // 2 kHz
        XCTAssertEqual(g[350], 4, accuracy: 1e-6)    // 7 kHz
    }

    func testNotAPhaseOrNonFiniteValues() {
        let m = PlotCurve(name: "m", x: [1, 2, 3], y: [1, 2, 3])
        XCTAssertEqual(m.groupDelay().y, m.y)
        let c = PlotCurve(name: "p", x: [0, 10, 20, 30, 40], y: [0, -10, .nan, -30, -40], phase: .degrees)
        let g = c.groupDelay().y
        XCTAssertTrue(g[2].isNaN)
        XCTAssertFalse(g[1].isNaN, "the neighbours that are finite are used across the gap")
        XCTAssertEqual(g[3], 1 / 360.0 * 1000, accuracy: 1e-9)   // −(−10°/10 Hz)/360 s
    }

    func testAGroupDelayIsSmoothedAsAPlainMean() {
        var y = [Double](repeating: 0, count: 4800)
        y[999] = 10                                          // one bin of 10 ms at 5 kHz
        let xs = (1...4800).map { Double($0) * 5 }
        var c = PlotCurve(name: "g", x: xs, y: y)
        c.isGroupDelay = true
        let s = c.smoothed(.third).y
        let inBand = s.filter { $0 > 0 }
        XCTAssertGreaterThan(inBand.count, 50)
        // A mean, not a mean of squares: a point that sees the spike has 10 / (number of points in its band), exactly.
        let bandPoints = s.enumerated().filter { $0.element > 0 }.count
        XCTAssertEqual(inBand.reduce(0, +) > 0, true)
        XCTAssertLessThan(s.max()!, 10)
        XCTAssertGreaterThan(bandPoints, 0)
        XCTAssertEqual(s[999], 10 / Double(s.filter { _ in true }.count > 0 ? bandWidth(at: 999, xs) : 1), accuracy: 1e-9)
    }

    private func bandWidth(at i: Int, _ xs: [Double]) -> Int {
        let half = pow(2, 1.0 / 6)
        return xs.filter { $0 >= xs[i] / half && $0 <= xs[i] * half }.count
    }
}
