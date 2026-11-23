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

    func testATraceAtAnotherRateIsPlacedByTime() {
        // The second trace has half the rate of the axis: its samples are two units of the axis apart (0, 2, 4).
        let c = SignalContent(traces: [PlotTrace(name: "fast", signal: PeakPyramid(samples: [0.1, 0.1, 0.1, 0.1, 0.1])),
                                       PlotTrace(name: "slow", signal: PeakPyramid(samples: [0.9, 0.9, 0.9]), timeScale: 2)],
                              sampleRate: 1000, amplitude: .linear)
        let t = transform(c, count: 5)
        let probe = c.probe(at: CGPoint(x: t.x(2), y: t.y(0.9)), t)
        XCTAssertEqual(probe.card, ["slow", "t = 2 ms", "n = 1", "0.9000  (−0.9 dB)"])
        XCTAssertEqual(c.measurePoint(at: CGPoint(x: t.x(4), y: t.y(0.9)), t).x, 4)
        XCTAssertEqual(PlotTrace(name: "", signal: PeakPyramid(samples: [0, 0]), timeScale: 0).timeScale, 1)
    }

    func testPaletteGivesEachTraceItsColour() {
        let palette = PlotPalette(accent: .purple, isDark: true)
        XCTAssertEqual(palette.trace(0), .purple)
        XCTAssertNotEqual(palette.trace(1), palette.trace(0))
        XCTAssertNotEqual(palette.trace(1), palette.trace(2))
        XCTAssertEqual(palette.trace(7, .red), .red)
        // Ten traces, ten colours.
        XCTAssertEqual(Set((0..<10).map { palette.trace($0) }).count, 10)
        // Each appearance starts with the colours that read best on its background, and has the same ten.
        let light = PlotPalette(accent: .purple, isDark: false)
        XCTAssertEqual(Set((0..<10).map { light.trace($0) }).count, 10)
        XCTAssertNotEqual(palette.trace(1), light.trace(1))
        XCTAssertEqual(Set(PlotTraceColors.dark), Set(PlotTraceColors.light))
        XCTAssertEqual(PlotTraceColors.adaptive.count, 9)
    }
}
