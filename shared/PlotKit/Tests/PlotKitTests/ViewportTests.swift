// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class ViewportTests: XCTestCase {
    private func axis(minSpan: Double = 0) -> AxisState { AxisState(bounds: 0...1000, minSpan: minSpan) }

    func testZoomKeepsTheAnchorWhereItIs() {
        let a = axis()
        let z = a.zoomed(by: 4, around: 250)
        XCTAssertEqual(z.fraction(of: 250), a.fraction(of: 250), accuracy: 1e-9)
        XCTAssertEqual(z.range.upperBound - z.range.lowerBound, 250, accuracy: 1e-9)
        let zz = z.zoomed(by: 2, around: 200)
        XCTAssertEqual(zz.fraction(of: 200), z.fraction(of: 200), accuracy: 1e-9)
    }

    func testZoomOutStopsAtTheBounds() {
        let z = axis().zoomed(by: 4, around: 500)
        XCTAssertEqual(z.zoomed(by: 0.001, around: 500).range, 0...1000)
        XCTAssertTrue(z.zoomed(by: 0.001, around: 500).isFitted)
        XCTAssertEqual(axis().zoomed(by: 0.5, around: 0).range, 0...1000)
    }

    func testZoomNearAnEdgeStaysInside() {
        let z = axis().zoomed(by: 10, around: 0)
        XCTAssertEqual(z.range.lowerBound, 0)
        let w = axis().zoomed(by: 10, around: 1000)
        XCTAssertEqual(w.range.upperBound, 1000)
        XCTAssertEqual(w.range.upperBound - w.range.lowerBound, 100, accuracy: 1e-9)
    }

    func testSmallestSpan() {
        let z = axis(minSpan: 8).zoomed(by: 1e9, around: 500)
        XCTAssertEqual(z.range.upperBound - z.range.lowerBound, 8, accuracy: 1e-9)
        let s = axis(minSpan: 8).showing(500...500.5)
        XCTAssertEqual(s.range.upperBound - s.range.lowerBound, 8, accuracy: 1e-9)
    }

    func testPanStopsAtTheBounds() {
        let z = axis().zoomed(by: 4, around: 500)   // 375...625
        XCTAssertEqual(z.panned(byFraction: 0.5).range.lowerBound, 500, accuracy: 1e-9)
        XCTAssertEqual(z.panned(byFraction: -100).range, 0...250)
        XCTAssertEqual(z.panned(byFraction: 100).range, 750...1000)
        XCTAssertEqual(axis().panned(byFraction: 1).range, 0...1000, "nothing to slide when everything is shown")
    }

    func testTheAxesAreIndependent() {
        var v = PlotViewport(x: axis(), y: AxisState(bounds: -1...1))
        v.x = v.x.zoomed(by: 10, around: 500)
        XCTAssertEqual(v.y.range, -1...1)
        XCTAssertFalse(v.isFitted)
        v.y = v.y.zoomed(by: 2, around: 0)
        XCTAssertEqual(v.y.range.upperBound, 0.5, accuracy: 1e-9)
        XCTAssertTrue(v.fitted().isFitted)
    }

    func testBoxZoom() {
        let v = PlotViewport(x: axis(), y: AxisState(bounds: -1...1)).zoomed(toX: 100...200, y: -0.5...0.25)
        XCTAssertEqual(v.x.range, 100...200)
        XCTAssertEqual(v.y.range.lowerBound, -0.5, accuracy: 1e-9)
        XCTAssertEqual(v.y.range.upperBound, 0.25, accuracy: 1e-9)
        let out = PlotViewport(x: axis(), y: AxisState(bounds: -1...1)).zoomed(toX: 900...1100, y: 0.5...2)
        XCTAssertEqual(out.x.range, 800...1000, "a box that reaches out of the bounds is brought back in, keeping its size")
    }

    func testAutoscaleOfTheVerticalAxis() {
        let v = PlotViewport(x: axis(), y: AxisState(bounds: -1...1)).autoscaledY(extremes: (-0.2, 0.8), margin: 0.1)
        XCTAssertEqual(v.y.range.lowerBound, -0.3, accuracy: 1e-9)
        XCTAssertEqual(v.y.range.upperBound, 0.9, accuracy: 1e-9)
        let base = PlotViewport(x: axis(), y: AxisState(bounds: -1...1))
        XCTAssertEqual(base.autoscaledY(extremes: nil), base)
        let flat = base.autoscaledY(extremes: (0.5, 0.5))
        XCTAssertGreaterThan(flat.y.range.upperBound - flat.y.range.lowerBound, 0.5)
    }

    func testLogarithmicAxis() {
        let a = AxisState(bounds: 20...20_000, scale: .logarithmic, minSpan: 1.05)
        let middle = sqrt(20 * 20_000.0)
        XCTAssertEqual(a.fraction(of: middle), 0.5, accuracy: 1e-12)
        let z = a.zoomed(by: 2, around: middle)
        XCTAssertEqual(z.fraction(of: middle), 0.5, accuracy: 1e-9)
        XCTAssertEqual(z.range.upperBound / z.range.lowerBound, sqrt(1000), accuracy: 1e-6)
        let deep = a.zoomed(by: 1e9, around: 1000)
        XCTAssertEqual(deep.range.upperBound / deep.range.lowerBound, 1.05, accuracy: 1e-9)
        XCTAssertEqual(z.fitted().range, 20...20_000)
        XCTAssertEqual(z.panned(byFraction: 100).range.upperBound, 20_000, accuracy: 1e-9)
    }

    func testBoundsChange() {
        let a = axis().zoomed(by: 4, around: 500)
        XCTAssertEqual(a.withBounds(0...2000).range, a.range, "the range is kept when it still fits")
        XCTAssertEqual(a.withBounds(400...600).range, 400...600, "else everything is shown")
    }

    func testTransform() {
        let viewport = PlotViewport(x: axis(), y: AxisState(bounds: -1...1))
        let t = PlotTransform(viewport: viewport, rect: CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(t.x(0), 10); XCTAssertEqual(t.x(1000), 110); XCTAssertEqual(t.x(500), 60)
        XCTAssertEqual(t.y(1), 20); XCTAssertEqual(t.y(-1), 70); XCTAssertEqual(t.y(0), 45)
        XCTAssertEqual(t.xValue(60), 500, accuracy: 1e-9)
        XCTAssertEqual(t.yValue(45), 0, accuracy: 1e-9)
        for v in [0.0, 123.4, 999.9] { XCTAssertEqual(t.xValue(t.x(v)), v, accuracy: 1e-6) }
        let empty = PlotTransform(viewport: viewport, rect: .zero)
        XCTAssertEqual(empty.xValue(5), 0)
    }
}

final class ScaleSwitchTests: XCTestCase {
    func testLinearToLogarithmicAndBack() {
        // The axis of a time signal in samples: from 0, which a logarithmic axis cannot show.
        var a = AxisState(bounds: 0...480_000, minSpan: 4)
        a = a.zoomed(by: 8, around: 100_000)
        let before = a.range
        let log = a.switched(to: .logarithmic, minSpan: 1.01, positiveFloor: 1)
        XCTAssertEqual(log.scale, .logarithmic)
        XCTAssertEqual(log.bounds, 1...480_000, "the bounds start at the floor")
        XCTAssertEqual(log.range, before, "a range that is positive is kept")
        let back = log.switched(to: .linear, minSpan: 4)
        XCTAssertEqual(back.bounds, 0...480_000, "the bounds of the data come back")
        XCTAssertEqual(back.range, before)
        XCTAssertEqual(a.switched(to: .linear, minSpan: 4), a, "the same scale changes nothing")
    }

    func testARangeThatTouchesZeroIsBroughtToTheFloor() {
        let a = AxisState(bounds: 0...1000, minSpan: 1)
        let log = a.switched(to: .logarithmic, minSpan: 1.01, positiveFloor: 1)
        XCTAssertEqual(log.range, 1...1000)
        XCTAssertEqual(log.fraction(of: sqrt(1000.0)), 0.5, accuracy: 1e-9)
        // A zoom on the logarithmic axis works with its new minimum span.
        let z = log.zoomed(by: 1e9, around: 30)
        XCTAssertEqual(z.range.upperBound / z.range.lowerBound, 1.01, accuracy: 1e-9)
    }

    func testFrequencyAxisBothWays() {
        let a = AxisState(bounds: 20...20_000, scale: .logarithmic, minSpan: 1.05)
        let linear = a.switched(to: .linear, minSpan: 1)
        XCTAssertEqual(linear.range, 20...20_000)
        XCTAssertEqual(linear.fraction(of: 10_010), 0.5, accuracy: 1e-3)
        XCTAssertEqual(linear.switched(to: .logarithmic, minSpan: 1.05).range, 20...20_000)
    }
}
