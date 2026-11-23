// SPDX-License-Identifier: MIT

import XCTest
import SwiftUI
@testable import PlotKit

@MainActor
final class SeriesTests: XCTestCase {
    private func signal(_ v: Float) -> PlotSignal { PeakPyramid(samples: [v, v, v, v]) }

    func testAChannelKeepsItsColourWhateverIsShown() {
        let set = PlotSeriesSet(count: 3, accent: .purple)
        let all = set.traces { signal(Float($0)) }
        XCTAssertEqual(all.map(\.color), [set.items[0].color, set.items[1].color, set.items[2].color])
        // Only the second channel: it keeps the colour it had with the others (not the accent a trace in first place would get).
        set.items[0].isVisible = false
        set.items[2].isVisible = false
        let alone = set.traces { signal(Float($0)) }
        XCTAssertEqual(alone.count, 1)
        XCTAssertEqual(alone[0].color, all[1].color)
        XCTAssertNotEqual(alone[0].color, set.items[0].color)
    }

    func testDefaultColoursAreThoseOfThePalette() {
        let set = PlotSeriesSet(count: 2, accent: .purple)
        XCTAssertEqual(set.items[0].color, .purple)
        // After the accent, the colours of the sequence that follow the appearance.
        XCTAssertEqual(set.items[1].color, PlotTraceColors.adaptive[0])
        XCTAssertEqual(PlotSeriesSet.defaultColor(1, accent: .purple), set.items[1].color)
    }

    func testAChosenColourIsUsedEverywhere() {
        let set = PlotSeriesSet(count: 2, accent: .purple)
        set.items[1].color = .orange
        XCTAssertEqual(set.traces { signal(Float($0)) }[1].color, .orange)
        let curves = set.curves { _ in ([1, 2, 3], [1, 2, 3]) }
        XCTAssertEqual(curves[1].color, .orange)
    }

    func testSoloShowsOneAndThenAllAgain() {
        let set = PlotSeriesSet(count: 3)
        set.solo(1)
        XCTAssertEqual(set.visible.map(\.id), [1])
        set.solo(1)
        XCTAssertEqual(set.visible.map(\.id), [0, 1, 2], "a second solo of the same channel brings the others back")
        set.solo(2)
        set.solo(0)
        XCTAssertEqual(set.visible.map(\.id), [0])
    }

    func testTheSeriesDoNotDecideTheGradient() {
        // Whether the area under a curve has a gradient is up to the plot and its display options, not to the set of channels.
        let set = PlotSeriesSet(count: 2)
        XCTAssertEqual(set.curves { _ in ([1, 2], [1, 2]) }.map(\.filled), [true, true])
        XCTAssertEqual(set.curves({ _ in ([1, 2], [1, 2]) }, filled: false).map(\.filled), [false, false])
    }

    func testNames() {
        let set = PlotSeriesSet(count: 3, names: ["L", "R"])
        XCTAssertEqual(set.items.map(\.name), ["L", "R", "3"])
    }
}

final class GradientPolicyTests: XCTestCase {
    func testByDefaultOneCurveHasAGradientAndSeveralAnOpaqueBody() {
        let g = PlotGradient()
        XCTAssertEqual(g.fill(curves: 1), .gradient(1))
        // The fill is never missing, and with several curves it is opaque: the one on top hides the ones under it.
        for n in [2, 3, 8] { XCTAssertEqual(g.fill(curves: n), .solid(0.5)) }
    }

    func testTheOptionsChangeTheStyleNotThePresenceOfTheFill() {
        guard case .flat(let one) = PlotGradient(enabled: false).fill(curves: 1) else { return XCTFail() }
        XCTAssertGreaterThan(one, 0, "gradient off: a flat fill, not nothing")
        XCTAssertEqual(PlotGradient(enabled: false, withSeveral: true).fill(curves: 3), PlotGradient(enabled: false).fill(curves: 3), "the main switch wins")
        guard case .gradient(let k) = PlotGradient(enabled: true, withSeveral: true).fill(curves: 3) else { return XCTFail() }
        XCTAssertGreaterThan(k, 0)
        XCTAssertLessThan(k, 1, "a little lighter than the gradient of a single curve")
    }
}

@MainActor
final class SeriesOrderTests: XCTestCase {
    private func signal() -> PlotSignal { PeakPyramid(samples: [0, 0, 0, 0]) }

    func testBringToFrontPutsAChannelFirstWithoutChangingColours() {
        let set = PlotSeriesSet(count: 3, accent: .purple)
        let colours = set.items.map(\.color)
        set.bringToFront(2)
        XCTAssertEqual(set.items.map(\.id), [2, 0, 1])
        XCTAssertEqual(set.items[0].color, colours[2], "the colour belongs to the channel, not to its place")
        let traces = set.traces { _ in signal() }
        XCTAssertEqual(traces.map(\.name), ["3", "1", "2"], "the first is drawn on top")
        XCTAssertEqual(traces[0].color, colours[2])
        set.bringToFront(2)
        XCTAssertEqual(set.items.map(\.id), [2, 0, 1], "already first: nothing moves")
    }

    func testDraggingARowReordersTheChannels() {
        let set = PlotSeriesSet(count: 4)
        set.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        XCTAssertEqual(set.items.map(\.id), [0, 3, 1, 2])
        set.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(set.items.map(\.id), [3, 1, 2, 0])
    }

    func testTheOrderIsKeptWhenSomeChannelsAreHidden() {
        let set = PlotSeriesSet(count: 3)
        set.bringToFront(1)
        set.items[0].isVisible = false
        XCTAssertEqual(set.visible.map(\.id), [0, 2], "the hidden one leaves, the others keep their order")
        set.items[0].isVisible = true
        XCTAssertEqual(set.visible.map(\.id), [1, 0, 2])
    }
}
