// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class TraceTests: XCTestCase {
    private func content(_ a: [Float], _ b: [Float]) -> SignalContent {
        SignalContent(traces: [PlotTrace(name: "L", signal: PeakPyramid(samples: a)), PlotTrace(name: "R", signal: PeakPyramid(samples: b))],
                      sampleRate: 1000, amplitude: .linear)
    }

    private func transform(_ c: SignalContent, count: Int) -> PlotTransform {
        PlotTransform(viewport: PlotViewport.signal(count: count), rect: CGRect(x: 0, y: 0, width: 800, height: 400))
    }

    func testTheProbeReadsTheTraceNearestThePointer() {
        let c = content([0.8, 0.8, 0.8, 0.8], [-0.5, -0.5, -0.5, -0.5])
        let t = transform(c, count: 4)
        let upper = c.probe(at: CGPoint(x: t.x(2), y: t.y(0.7)), t)
        XCTAssertTrue(upper.onData)
        XCTAssertEqual(upper.card.first, "L")
        let lower = c.probe(at: CGPoint(x: t.x(2), y: t.y(-0.4)), t)
        XCTAssertEqual(lower.card.first, "R")
        XCTAssertEqual(lower.yFlag, "−0.500")
    }

    func testASingleTraceHasNoNameInTheCard() {
        let c = SignalContent(traces: [PlotTrace(name: "", signal: PeakPyramid(samples: [0.5, 0.5, 0.5, 0.5]))], sampleRate: 1000, amplitude: .linear)
        let t = transform(c, count: 4)
        XCTAssertEqual(c.probe(at: CGPoint(x: t.x(1), y: t.y(0.5)), t).card.first, "t = 1 ms")
    }

    func testAutoscaleCoversEveryTrace() {
        let c = content([0.1, 0.2, 0.1, 0.2], [-0.6, -0.7, -0.6, -0.7])
        let scaled = c.autoscale(PlotViewport.signal(count: 4))
        XCTAssertLessThan(scaled.y.range.lowerBound, -0.7)
        XCTAssertGreaterThan(scaled.y.range.upperBound, 0.2)
    }

    func testTracesOfDifferentLengthsAreAllowed() {
        let c = content([0.5, 0.5], [0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
        let t = transform(c, count: 6)
        // Past the end of the short one, only the long one answers.
        let probe = c.probe(at: CGPoint(x: t.x(5), y: t.y(0.5)), t)
        XCTAssertEqual(probe.card.first, "R")
    }

    func testPaletteGivesEachTraceItsColour() {
        let palette = PlotPalette(accent: .purple, isDark: true)
        XCTAssertEqual(palette.trace(0), .purple)
        XCTAssertNotEqual(palette.trace(1), palette.trace(0))
        XCTAssertNotEqual(palette.trace(1), palette.trace(2))
        XCTAssertEqual(palette.trace(7, .red), .red)
    }
}
