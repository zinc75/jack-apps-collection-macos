// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Where the parts of a plot are in its view: the plot area, and the strips of the two axes under and beside it. The
/// drawing and the mouse use the same layout, so what is drawn is what is hit.
public struct PlotLayout: Equatable, Sendable {
    public var size: CGSize
    public var plot: CGRect
    /// The strip right under the plot that holds the sliders of an editable region (empty when there is none).
    public var rail: CGRect
    /// The strip under the plot (and its rail), where the labels of the horizontal axis are.
    public var xAxis: CGRect
    /// The strip left of the plot, where the labels of the vertical axis are.
    public var yAxis: CGRect

    public static let left: CGFloat = 66, bottom: CGFloat = 42, top: CGFloat = 12, right: CGFloat = 18

    /// - Parameter railHeight: the height of the strip of the sliders of a region, between the plot and the labels of its axis.
    public init(size: CGSize, railHeight: CGFloat = 0) {
        self.size = size
        let width = max(0, size.width - Self.left - Self.right), height = max(0, size.height - Self.top - Self.bottom - railHeight)
        plot = CGRect(x: Self.left, y: Self.top, width: width, height: height)
        rail = CGRect(x: plot.minX, y: plot.maxY, width: width, height: railHeight)
        xAxis = CGRect(x: plot.minX, y: plot.maxY + railHeight, width: width, height: Self.bottom)
        yAxis = CGRect(x: 0, y: plot.minY, width: Self.left, height: height)
    }

    /// What a point of the view is over.
    public enum Region: Equatable, Sendable {
        case plot
        case xAxis(AxisPart)
        case yAxis(AxisPart)
        case outside
    }

    public func region(at p: CGPoint) -> Region {
        if plot.contains(p) { return .plot }
        if xAxis.contains(p) { return .xAxis(AxisPart.of(fraction: Double((p.x - xAxis.minX) / max(1, xAxis.width)))) }
        if yAxis.contains(p) {
            // The vertical axis grows upwards.
            return .yAxis(AxisPart.of(fraction: Double((yAxis.maxY - p.y) / max(1, yAxis.height))))
        }
        return .outside
    }
}

/// Which part of an axis a drag starts on, as Plotly does it: the middle slides the range, an end changes the scale (the
/// other end stays).
public enum AxisPart: Equatable, Sendable {
    case lowEnd, middle, highEnd

    static let endShare = 0.22

    public static func of(fraction f: Double) -> AxisPart {
        f < endShare ? .lowEnd : (f > 1 - endShare ? .highEnd : .middle)
    }
}
