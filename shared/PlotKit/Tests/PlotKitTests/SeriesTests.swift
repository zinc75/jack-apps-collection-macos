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
        XCTAssertEqual(set.items[1].color, PlotPalette(accent: .purple, isDark: false).trace(1))
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

    func testOnlyAloneCurveHasTheGradient() {
        let set = PlotSeriesSet(count: 2)
        let both = set.curves { _ in ([1, 2], [1, 2]) }
        XCTAssertEqual(both.map(\.filled), [false, false])
        set.items[1].isVisible = false
        XCTAssertEqual(set.curves { _ in ([1, 2], [1, 2]) }.map(\.filled), [true])
    }

    func testNames() {
        let set = PlotSeriesSet(count: 3, names: ["L", "R"])
        XCTAssertEqual(set.items.map(\.name), ["L", "R", "3"])
    }
}
