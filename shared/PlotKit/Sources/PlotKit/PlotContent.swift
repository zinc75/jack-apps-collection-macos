// SPDX-License-Identifier: MIT

import SwiftUI

/// What the crosshair reads under the pointer: where it is drawn (on a data point when there is one near), the texts of the two
/// flags on the axes, and the lines of the card when it is on a data point.
struct PlotProbe {
    var point: CGPoint
    var xFlag: String
    var yFlag: String
    var card: [String]
    var onData: Bool
    /// The trace the point is on (it gives the colour of the marker and of the flags), and its own colour if it has one.
    var trace = 0
    var customColor: Color?
}

/// What differs between the plots, so that the axes, the crosshair, the measure, the gestures and the toolbar are written once:
/// how the data are drawn, how they are read off under the pointer, and the units.
protocol PlotContent {
    /// The unit of the horizontal axis ("s", "Hz"), which gets a prefix (m, k) on a linear axis; empty for a plain number.
    var xUnit: String { get }
    /// The values of the axis divided by this are what the graduations show (the sample rate, for a time axis in samples).
    var xDivisor: Double { get }
    /// Whether the graduations of a linear axis are whole numbers (sample numbers).
    var xIntegers: Bool { get }
    /// What is written under the axis when it has no unit.
    var xCaption: String { get }
    /// The unit written along the vertical axis ("dB", "°"); empty for none.
    var yUnit: String { get }
    /// Whether a line is drawn at zero.
    var hasZeroLine: Bool { get }
    /// What a measure depends on: when it changes, a measure means nothing any more.
    var measureKey: AnyHashable { get }

    func drawData(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ scale: CGFloat, _ cache: EnvelopeCache)
    func probe(at p: CGPoint, _ t: PlotTransform) -> PlotProbe
    /// A point of the view as a point of the data for a measure.
    func measurePoint(at p: CGPoint, _ t: PlotTransform) -> (x: Double, y: Double)
    func measureReadout(_ m: PlotSegment) -> [String]
    /// The vertical axis fitted to what the horizontal range shows.
    func autoscale(_ v: PlotViewport) -> PlotViewport
}
