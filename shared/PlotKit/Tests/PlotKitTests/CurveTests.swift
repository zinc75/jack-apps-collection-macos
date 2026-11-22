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
