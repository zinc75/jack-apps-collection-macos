// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class GestureTests: XCTestCase {
    private let rect = CGRect(x: 60, y: 12, width: 1000, height: 400)
    private func viewport() -> PlotViewport { PlotViewport(x: AxisState(bounds: 0...10_000), y: AxisState(bounds: -1...1)) }
    private func transform(_ v: PlotViewport) -> PlotTransform { PlotTransform(viewport: v, rect: rect) }

    func testZoomKeepsTheValueUnderThePointer() {
        let v = viewport()
        let anchor = CGPoint(x: 260, y: 100)
        let before = transform(v)
        let z = PlotGestures.zoom(v, axes: .both, factor: 3, anchor: anchor, in: before)
        let after = transform(z)
        XCTAssertEqual(after.x(before.xValue(anchor.x)), anchor.x, accuracy: 1e-6)
        XCTAssertEqual(after.y(before.yValue(anchor.y)), anchor.y, accuracy: 1e-6)
        XCTAssertLessThan(z.x.range.upperBound - z.x.range.lowerBound, 10_000)
        let onlyX = PlotGestures.zoom(v, axes: .x, factor: 3, anchor: anchor, in: before)
        XCTAssertEqual(onlyX.y, v.y)
        let onlyY = PlotGestures.zoom(v, axes: .y, factor: 3, anchor: anchor, in: before)
        XCTAssertEqual(onlyY.x, v.x)
    }

    func testPanFollowsThePointer() {
        let zoomed = PlotGestures.zoom(viewport(), axes: .both, factor: 4, anchor: CGPoint(x: 560, y: 212), in: transform(viewport()))
        let t = transform(zoomed)
        let dragged = PlotGestures.pan(zoomed, byPixels: CGSize(width: 100, height: -40), in: t)
        let moved = transform(dragged)
        // The value that was under the start of the drag is now under its end.
        let start = CGPoint(x: 400, y: 200)
        let value = (t.xValue(start.x), t.yValue(start.y))
        XCTAssertEqual(moved.x(value.0), start.x + 100, accuracy: 1e-6)
        XCTAssertEqual(moved.y(value.1), start.y - 40, accuracy: 1e-6)
    }

    func testBoxZoom() {
        let v = viewport()
        let t = transform(v)
        let z = PlotGestures.zoomBox(v, from: CGPoint(x: 160, y: 62), to: CGPoint(x: 360, y: 162), in: t)
        XCTAssertEqual(z.x.range.lowerBound, 1000, accuracy: 1e-6)
        XCTAssertEqual(z.x.range.upperBound, 3000, accuracy: 1e-6)
        XCTAssertEqual(z.y.range.upperBound, t.yValue(62), accuracy: 1e-9)
        // The corners may be given in any order.
        let same = PlotGestures.zoomBox(v, from: CGPoint(x: 360, y: 162), to: CGPoint(x: 160, y: 62), in: t)
        XCTAssertEqual(same, z)
        // A click is not a box; a box thin in one direction zooms the other axis only.
        XCTAssertEqual(PlotGestures.zoomBox(v, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 101), in: t), v)
        let band = PlotGestures.zoomBox(v, from: CGPoint(x: 160, y: 100), to: CGPoint(x: 360, y: 101), in: t)
        XCTAssertEqual(band.y, v.y)
        XCTAssertNotEqual(band.x, v.x)
    }

    func testAxisDrag() {
        var axis = AxisState(bounds: 0...1000)
        axis = axis.zoomed(by: 4, around: 500)   // 375...625
        // The middle slides: dragging 100 points of 1000 to the right shows what is 10 % to the left.
        let slid = PlotGestures.axisDrag(axis, part: .middle, delta: 100, length: 1000)
        XCTAssertEqual(slid.range.lowerBound, 375 - 25, accuracy: 1e-9)
        XCTAssertEqual(slid.range.upperBound - slid.range.lowerBound, 250, accuracy: 1e-9)
        // An end changes the scale, the other end stays.
        let high = PlotGestures.axisDrag(axis, part: .highEnd, delta: -200, length: 1000)
        XCTAssertEqual(high.range.lowerBound, 375, accuracy: 1e-9)
        XCTAssertEqual(high.range.upperBound, 375 + 250 * 0.8, accuracy: 1e-9)
        let low = PlotGestures.axisDrag(axis, part: .lowEnd, delta: 200, length: 1000)
        XCTAssertEqual(low.range.upperBound, 625, accuracy: 1e-9)
        XCTAssertEqual(low.range.lowerBound, 375 + 250 * 0.2, accuracy: 1e-9)
        XCTAssertEqual(PlotGestures.axisDrag(axis, part: .middle, delta: 5, length: 0), axis)
    }

    func testLayoutRegions() {
        let layout = PlotLayout(size: CGSize(width: 800, height: 400))
        XCTAssertEqual(layout.region(at: CGPoint(x: 300, y: 100)), .plot)
        XCTAssertEqual(layout.region(at: CGPoint(x: 300, y: 400 - 10)), .xAxis(.middle))
        XCTAssertEqual(layout.region(at: CGPoint(x: PlotLayout.left + 5, y: 400 - 10)), .xAxis(.lowEnd))
        XCTAssertEqual(layout.region(at: CGPoint(x: 800 - PlotLayout.right - 5, y: 400 - 10)), .xAxis(.highEnd))
        XCTAssertEqual(layout.region(at: CGPoint(x: 20, y: 200)), .yAxis(.middle))
        XCTAssertEqual(layout.region(at: CGPoint(x: 20, y: PlotLayout.top + 5)), .yAxis(.highEnd), "the vertical axis grows upwards")
        XCTAssertEqual(layout.region(at: CGPoint(x: 790, y: 5)), .outside)
        XCTAssertEqual(PlotLayout(size: CGSize(width: 10, height: 10)).plot.width, 0)
    }

    func testScrollAndPinchFactors() {
        XCTAssertGreaterThan(PlotGestures.factor(forScroll: 5), 1)
        XCTAssertLessThan(PlotGestures.factor(forScroll: -5), 1)
        XCTAssertEqual(PlotGestures.factor(forScroll: 5) * PlotGestures.factor(forScroll: -5), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(PlotGestures.factor(forMagnification: 0.1), 1)
    }
}

final class ZoomAxesTests: XCTestCase {
    func testModifiersChooseTheAxes() {
        XCTAssertEqual(PlotGestures.axes(option: false, shift: false), .x)
        XCTAssertEqual(PlotGestures.axes(option: true, shift: false), .y)
        XCTAssertEqual(PlotGestures.axes(option: false, shift: true), .both)
        XCTAssertEqual(PlotGestures.axes(option: true, shift: true), .both)
    }
}
