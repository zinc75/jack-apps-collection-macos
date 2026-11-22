// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class RegionTests: XCTestCase {
    private let plot = CGRect(x: 50, y: 10, width: 500, height: 300)

    func testEdgesInThePlot() {
        // The region is from x = 100 to x = 300 on the screen: its edges are taken in the plot, and nothing else is.
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 102, y: 150), lo: 100, hi: 300, plot: plot), .start)
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 297, y: 200), lo: 100, hi: 300, plot: plot), .end)
        XCTAssertNil(PlotRegionMath.part(at: CGPoint(x: 200, y: 150), lo: 100, hi: 300, plot: plot))
        XCTAssertNil(PlotRegionMath.part(at: CGPoint(x: 200, y: 15), lo: 100, hi: 300, plot: plot))
        XCTAssertNil(PlotRegionMath.part(at: CGPoint(x: 400, y: 150), lo: 100, hi: 300, plot: plot))
    }

    /// The rail under the plot: its knobs stretch the region, the part between them slides it.
    func testRailKnobsAndSlide() {
        let rail = CGRect(x: 50, y: 310, width: 500, height: 28)
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 105, y: 322), lo: 100, hi: 300, plot: plot, rail: rail), .start)
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 295, y: 330), lo: 100, hi: 300, plot: plot, rail: rail), .end)
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 200, y: 322), lo: 100, hi: 300, plot: plot, rail: rail), .move)
        // On the rail but outside the region there is nothing to take.
        XCTAssertNil(PlotRegionMath.part(at: CGPoint(x: 450, y: 322), lo: 100, hi: 300, plot: plot, rail: rail))
        // A knob and an edge are reached from the plot too.
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 102, y: 150), lo: 100, hi: 300, plot: plot, rail: rail), .start)
    }

    /// The layout leaves room for the rail between the plot and the labels of the axis.
    func testLayoutWithARail() {
        let plain = PlotLayout(size: CGSize(width: 800, height: 400))
        let railed = PlotLayout(size: CGSize(width: 800, height: 400), railHeight: 28)
        XCTAssertEqual(railed.plot.height, plain.plot.height - 28)
        XCTAssertEqual(railed.rail.minY, railed.plot.maxY)
        XCTAssertEqual(railed.xAxis.minY, railed.rail.maxY)
        XCTAssertEqual(plain.rail.height, 0)
    }

    /// A region so narrow that both handles are within reach: the side of the pointer decides.
    func testNarrowRegion() {
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 101, y: 100), lo: 100, hi: 106, plot: plot), .start)
        XCTAssertEqual(PlotRegionMath.part(at: CGPoint(x: 105, y: 100), lo: 100, hi: 106, plot: plot), .end)
    }

    func testDragStartAndEnd() {
        let style = PlotRegionStyle(minLength: 10, bounds: 0...1000)
        XCTAssertEqual(PlotRegionMath.dragged(.start, from: 100...400, by: 50.4, style: style), 150...400)
        // It cannot pass the end (minus the smallest length) or leave the bounds.
        XCTAssertEqual(PlotRegionMath.dragged(.start, from: 100...400, by: 900, style: style), 390...400)
        XCTAssertEqual(PlotRegionMath.dragged(.start, from: 100...400, by: -900, style: style), 0...400)
        XCTAssertEqual(PlotRegionMath.dragged(.end, from: 100...400, by: -900, style: style), 100...110)
        XCTAssertEqual(PlotRegionMath.dragged(.end, from: 100...400, by: 900, style: style), 100...1000)
    }

    func testDragMoveKeepsTheLength() {
        let style = PlotRegionStyle(minLength: 10, bounds: 0...1000)
        XCTAssertEqual(PlotRegionMath.dragged(.move, from: 100...400, by: 200, style: style), 300...600)
        XCTAssertEqual(PlotRegionMath.dragged(.move, from: 100...400, by: 5000, style: style), 700...1000)
        XCTAssertEqual(PlotRegionMath.dragged(.move, from: 100...400, by: -5000, style: style), 0...300)
    }

    func testSnapAndNoSnap() {
        var style = PlotRegionStyle(minLength: 0.5)
        XCTAssertEqual(PlotRegionMath.dragged(.start, from: 10...20, by: 1.6, style: style), 12...20)
        style.snapsToIntegers = false
        XCTAssertEqual(PlotRegionMath.dragged(.start, from: 10...20, by: 1.6, style: style).lowerBound, 11.6, accuracy: 1e-12)
    }
}

final class OverviewTests: XCTestCase {
    func testPressNearAnEdgeTakesIt() {
        let window = 200.0...400.0
        XCTAssertEqual(PlotOverviewMath.begin(at: 52, lo: 50, hi: 150, window: window, valueAtPointer: 210), .start(fixedEnd: 400))
        XCTAssertEqual(PlotOverviewMath.begin(at: 148, lo: 50, hi: 150, window: window, valueAtPointer: 390), .end(fixedStart: 200))
    }

    func testPressInsideSlidesAndOutsideCentres() {
        let window = 200.0...400.0
        XCTAssertEqual(PlotOverviewMath.begin(at: 100, lo: 50, hi: 150, window: window, valueAtPointer: 300), .slide(grab: 100))
        // Outside the window: it is brought under the pointer, which holds its middle.
        XCTAssertEqual(PlotOverviewMath.begin(at: 300, lo: 50, hi: 150, window: window, valueAtPointer: 700), .slide(grab: 100))
    }

    func testWindowAfterMoves() {
        let original = 200.0...400.0
        XCTAssertEqual(PlotOverviewMath.window(for: .start(fixedEnd: 400), original: original, value: 100, minSpan: 4), 100...400)
        XCTAssertEqual(PlotOverviewMath.window(for: .start(fixedEnd: 400), original: original, value: 500, minSpan: 4), 396...400)
        XCTAssertEqual(PlotOverviewMath.window(for: .end(fixedStart: 200), original: original, value: 100, minSpan: 4), 200...204)
        XCTAssertEqual(PlotOverviewMath.window(for: .slide(grab: 100), original: original, value: 600, minSpan: 4), 500...700)
    }
}

final class CursorRectTests: XCTestCase {
    private let plot = CGRect(x: 50, y: 10, width: 500, height: 300)

    /// A handle that the zoom took out of the view has no cursor rectangle (AppKit raises an exception for an empty one).
    func testHandleOutsideTheView() {
        XCTAssertNil(PlotCursorRect(rect: CGRect(x: 700, y: 10, width: 12, height: 300), kind: .resizeHorizontal).clipped(to: plot))
        XCTAssertNil(PlotCursorRect(rect: CGRect(x: -400, y: 10, width: 12, height: 300), kind: .resizeHorizontal).clipped(to: plot))
    }

    func testPartlyInsideIsCut() {
        let r = PlotCursorRect(rect: CGRect(x: 40, y: 10, width: 24, height: 300), kind: .resizeHorizontal).clipped(to: plot)
        XCTAssertEqual(r, CGRect(x: 50, y: 10, width: 14, height: 300))
    }

    func testNotFiniteAndEmpty() {
        XCTAssertNil(PlotCursorRect(rect: CGRect(x: CGFloat.nan, y: 10, width: 12, height: 300), kind: .grab).clipped(to: plot))
        XCTAssertNil(PlotCursorRect(rect: CGRect(x: CGFloat.infinity, y: 10, width: 12, height: 300), kind: .grab).clipped(to: plot))
        XCTAssertNil(PlotCursorRect(rect: CGRect(x: 100, y: 10, width: 0, height: 300), kind: .grab).clipped(to: plot))
    }
}
