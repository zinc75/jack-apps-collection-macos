// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// How an axis maps values to positions.
public enum AxisScale: Sendable, Equatable {
    case linear, logarithmic

    /// The value in the space where a position is proportional to the distance (the logarithm on a logarithmic axis).
    func forward(_ v: Double) -> Double { self == .linear ? v : log10(max(v, .leastNormalMagnitude)) }
    func inverse(_ u: Double) -> Double { self == .linear ? u : pow(10, u) }
}

/// One axis of a plot: the range that is shown, the range of everything there is, and how far one can zoom in. Every
/// operation returns a new state that stays inside the bounds, so a gesture cannot leave the data.
public struct AxisState: Equatable, Sendable {
    public var scale: AxisScale
    public private(set) var range: ClosedRange<Double>
    public private(set) var bounds: ClosedRange<Double>
    /// The smallest span that can be shown, in the units of the axis (on a logarithmic axis, as a ratio of the ends).
    public var minSpan: Double

    public init(bounds: ClosedRange<Double>, scale: AxisScale = .linear, minSpan: Double = 0) {
        self.scale = scale
        self.bounds = bounds
        self.range = bounds
        self.minSpan = minSpan
    }

    private var u: ClosedRange<Double> { scale.forward(range.lowerBound)...scale.forward(range.upperBound) }
    private var boundsU: ClosedRange<Double> { scale.forward(bounds.lowerBound)...scale.forward(bounds.upperBound) }
    private var minSpanU: Double { scale == .linear ? minSpan : log10(max(minSpan, 1 + 1e-12)) }

    public var isFitted: Bool { range == bounds }

    /// Where a value is in the range, from 0 (its start) to 1 (its end); outside it for a value outside the range.
    public func fraction(of value: Double) -> Double {
        let r = u
        let span = r.upperBound - r.lowerBound
        return span > 0 ? (scale.forward(value) - r.lowerBound) / span : 0
    }

    /// The value at a place of the range, from 0 to 1.
    public func value(atFraction f: Double) -> Double {
        let r = u
        return scale.inverse(r.lowerBound + f * (r.upperBound - r.lowerBound))
    }

    private func with(uLow: Double, uHigh: Double) -> AxisState {
        var out = self
        let b = boundsU
        let boundsSpan = b.upperBound - b.lowerBound
        var span = min(max(uHigh - uLow, min(minSpanU, boundsSpan)), boundsSpan)
        if !span.isFinite || span <= 0 { span = boundsSpan }
        // Keep the centre of what was asked, then slide the range back inside the bounds.
        let centre = (uLow + uHigh) / 2
        var low = centre - span / 2
        if low < b.lowerBound { low = b.lowerBound }
        if low + span > b.upperBound { low = b.upperBound - span }
        let a = scale.inverse(low), c = scale.inverse(low + span)
        // The ends of the bounds themselves, not their round trip through the logarithm.
        out.range = (low <= b.lowerBound ? bounds.lowerBound : a)...(low + span >= b.upperBound ? bounds.upperBound : c)
        return out
    }

    /// Zooms by a factor (more than 1 zooms in) with `anchor`, a value of the axis, staying where it is on the screen.
    public func zoomed(by factor: Double, around anchor: Double) -> AxisState {
        guard factor > 0, factor.isFinite else { return self }
        let r = u
        let ua = scale.forward(anchor)
        let span = r.upperBound - r.lowerBound
        let frac = span > 0 ? (ua - r.lowerBound) / span : 0.5
        let newSpan = min(max(span / factor, min(minSpanU, boundsSpanU)), boundsSpanU)
        let low = ua - frac * newSpan
        return with(uLow: low, uHigh: low + newSpan)
    }

    private var boundsSpanU: Double { boundsU.upperBound - boundsU.lowerBound }

    /// Slides the range by a fraction of its own span (positive towards larger values).
    public func panned(byFraction f: Double) -> AxisState {
        let r = u
        let d = f * (r.upperBound - r.lowerBound)
        return with(uLow: r.lowerBound + d, uHigh: r.upperBound + d)
    }

    /// Shows a range of values (a box zoom, a handle of a minimap), kept inside the bounds and above the smallest span.
    public func showing(_ values: ClosedRange<Double>) -> AxisState {
        with(uLow: scale.forward(values.lowerBound), uHigh: scale.forward(values.upperBound))
    }

    /// Shows everything.
    public func fitted() -> AxisState {
        var out = self
        out.range = bounds
        return out
    }

    /// New bounds (the data changed): the range is kept when it still fits, else everything is shown.
    public func withBounds(_ new: ClosedRange<Double>) -> AxisState {
        var out = self
        out.bounds = new
        if range.lowerBound < new.lowerBound || range.upperBound > new.upperBound { out.range = new }
        return out
    }
}

/// The two axes of a plot, each with its own range: one can zoom or slide one without the other, as Plotly lets the person
/// drag on an axis, and zoom to a box.
public struct PlotViewport: Equatable, Sendable {
    public var x: AxisState
    public var y: AxisState

    public init(x: AxisState, y: AxisState) {
        self.x = x
        self.y = y
    }

    public var isFitted: Bool { x.isFitted && y.isFitted }

    /// The zoom to a box drawn with the mouse.
    public func zoomed(toX xs: ClosedRange<Double>, y ys: ClosedRange<Double>) -> PlotViewport {
        PlotViewport(x: x.showing(xs), y: y.showing(ys))
    }

    /// Autoscale: the vertical range that holds what the horizontal range shows (`extremes` of the signal in it), with a
    /// margin of a fraction of that range. With nothing in it, the vertical range is kept.
    public func autoscaledY(extremes: (min: Double, max: Double)?, margin: Double = 0.06) -> PlotViewport {
        guard let e = extremes, e.max.isFinite, e.min.isFinite else { return self }
        var low = e.min, high = e.max
        if high - low < 1e-12 { low -= 0.5; high += 0.5 }
        let pad = (high - low) * margin
        var out = self
        out.y = y.showing((low - pad)...(high + pad))
        return out
    }

    public func fitted() -> PlotViewport { PlotViewport(x: x.fitted(), y: y.fitted()) }
}

/// Between values and places of the plot area, in points. The origin of the vertical axis is at the bottom.
public struct PlotTransform: Sendable {
    public var viewport: PlotViewport
    public var rect: CGRect

    public init(viewport: PlotViewport, rect: CGRect) {
        self.viewport = viewport
        self.rect = rect
    }

    public func x(_ value: Double) -> CGFloat { rect.minX + CGFloat(viewport.x.fraction(of: value)) * rect.width }
    public func y(_ value: Double) -> CGFloat { rect.maxY - CGFloat(viewport.y.fraction(of: value)) * rect.height }
    public func point(x vx: Double, y vy: Double) -> CGPoint { CGPoint(x: x(vx), y: y(vy)) }

    public func xValue(_ px: CGFloat) -> Double {
        rect.width > 0 ? viewport.x.value(atFraction: Double((px - rect.minX) / rect.width)) : viewport.x.range.lowerBound
    }
    public func yValue(_ py: CGFloat) -> Double {
        rect.height > 0 ? viewport.y.value(atFraction: Double((rect.maxY - py) / rect.height)) : viewport.y.range.lowerBound
    }
}
