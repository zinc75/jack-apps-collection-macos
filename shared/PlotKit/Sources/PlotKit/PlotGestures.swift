// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// What the mouse and the trackpad do to the viewport, as functions: the same ones for any view that draws a plot, and
/// testable without a window. Positions are in points of the view; `transform` maps the plot area.
public enum PlotGestures {
    public enum Axes: Sendable { case x, y, both }

    /// The axes a zoom acts on, from the modifier keys, the same for the wheel, a pinch and the buttons of the toolbar: none is
    /// the horizontal axis, ⌥ the vertical axis, ⇧ both.
    public static func axes(option: Bool, shift: Bool) -> Axes { shift ? .both : (option ? .y : .x) }

    /// Zooms around the pixel `anchor`: the value under it stays under it. A factor above 1 zooms in.
    public static func zoom(_ v: PlotViewport, axes: Axes, factor: Double, anchor: CGPoint, in transform: PlotTransform) -> PlotViewport {
        var out = v
        if axes != .y { out.x = v.x.zoomed(by: factor, around: transform.xValue(anchor.x)) }
        if axes != .x { out.y = v.y.zoomed(by: factor, around: transform.yValue(anchor.y)) }
        return out
    }

    /// Slides by a number of pixels: the content follows the pointer (a drag to the right shows what is to the left).
    public static func pan(_ v: PlotViewport, byPixels d: CGSize, in transform: PlotTransform) -> PlotViewport {
        var out = v
        let w = transform.rect.width, h = transform.rect.height
        if w > 0 { out.x = v.x.panned(byFraction: -Double(d.width / w)) }
        if h > 0 { out.y = v.y.panned(byFraction: Double(d.height / h)) }
        return out
    }

    /// The zoom to the box between two pixels. A box that is only a click (a few points) does nothing.
    public static func zoomBox(_ v: PlotViewport, from a: CGPoint, to b: CGPoint, in transform: PlotTransform) -> PlotViewport {
        guard abs(a.x - b.x) >= 4 || abs(a.y - b.y) >= 4 else { return v }
        let xs = [transform.xValue(a.x), transform.xValue(b.x)].sorted()
        let ys = [transform.yValue(a.y), transform.yValue(b.y)].sorted()
        var out = v
        // A box that is thin in one direction only (under 4 points) zooms the other axis alone.
        if abs(a.x - b.x) >= 4 { out.x = v.x.showing(xs[0]...xs[1]) }
        if abs(a.y - b.y) >= 4 { out.y = v.y.showing(ys[0]...ys[1]) }
        return out
    }

    /// A drag on an axis: from the range it had when the drag began, by a number of points along it. The middle slides it;
    /// an end moves that end only (towards the centre it zooms in), the other end stays.
    /// - Parameters:
    ///   - length: the length of the axis in points.
    ///   - delta: the movement of the pointer, in points, positive towards larger values.
    public static func axisDrag(_ start: AxisState, part: AxisPart, delta: Double, length: Double) -> AxisState {
        guard length > 0 else { return start }
        let f = delta / length
        switch part {
        case .middle:
            return start.panned(byFraction: -f)
        case .lowEnd:
            // The low end follows the pointer: the range becomes shorter when it moves up.
            return start.showing(start.value(atFraction: f)...start.range.upperBound)
        case .highEnd:
            return start.showing(start.range.lowerBound...start.value(atFraction: 1 + f))
        }
    }

    /// The factor of a zoom for a scroll of the wheel (`delta` in points, positive scrolls up) or a pinch (`magnification`).
    public static func factor(forScroll delta: Double) -> Double { exp(delta * 0.01) }
    public static func factor(forMagnification m: Double) -> Double { exp(m * 1.5) }

    /// The factor of the buttons of the zoom.
    public static let buttonFactor = 1.6
}
