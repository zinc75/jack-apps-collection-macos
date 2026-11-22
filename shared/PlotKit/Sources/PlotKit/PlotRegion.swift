// SPDX-License-Identifier: MIT

import SwiftUI

/// How an editable region looks and what it may be.
public struct PlotRegionStyle: Equatable {
    public var color: Color
    /// The smallest length, in the units of the horizontal axis.
    public var minLength: Double
    /// What the region cannot leave, in the units of the horizontal axis; `nil` for no limit.
    public var bounds: ClosedRange<Double>?
    /// The ends are whole numbers (sample numbers).
    public var snapsToIntegers: Bool
    /// Written in the bar of the region when it is wide enough.
    public var name: String

    public init(color: Color = .accentColor, minLength: Double = 1, bounds: ClosedRange<Double>? = nil, snapsToIntegers: Bool = true, name: String = "") {
        self.color = color
        self.minLength = minLength
        self.bounds = bounds
        self.snapsToIntegers = snapsToIntegers
        self.name = name
    }
}

/// A range of the horizontal axis that the person can change in the plot: two handles on its edges and a bar over it to slide it. What
/// is outside is dimmed and its edges are dotted lines. The range is updated while a handle is dragged; `onCommit` is called when the
/// drag ends, so that an application that keeps an undo history records one change, not one per movement.
public struct PlotRegionEditor {
    public var range: Binding<ClosedRange<Double>>
    public var style: PlotRegionStyle
    public var onCommit: () -> Void

    public init(range: Binding<ClosedRange<Double>>, style: PlotRegionStyle = PlotRegionStyle(), onCommit: @escaping () -> Void = {}) {
        self.range = range
        self.style = style
        self.onCommit = onCommit
    }
}

/// What a drag on a region moves.
public enum PlotRegionPart: Equatable, Sendable { case start, end, move }

/// Where the handles are and what a drag does to the range: apart from the view so that it can be tested.
enum PlotRegionMath {
    /// How near the pointer must be to an edge to take its handle, in points.
    static let tolerance: CGFloat = 6
    /// The height of the bar that slides the region, at the top of the plot.
    static let barHeight: CGFloat = 16

    /// The part of the region under a point of the view, given where its edges are on the screen (`lo` and `hi`).
    static func part(at p: CGPoint, lo: CGFloat, hi: CGFloat, plot: CGRect) -> PlotRegionPart? {
        guard p.y >= plot.minY, p.y <= plot.maxY, p.x >= plot.minX - tolerance, p.x <= plot.maxX + tolerance else { return nil }
        let nearLo = abs(p.x - lo) <= tolerance, nearHi = abs(p.x - hi) <= tolerance
        if nearLo || nearHi {
            if nearLo && nearHi { return p.x < (lo + hi) / 2 ? .start : .end }
            return nearLo ? .start : .end
        }
        if p.y <= plot.minY + barHeight, p.x > lo, p.x < hi { return .move }
        return nil
    }

    /// The range after a drag of `delta` (in the units of the axis) on a part, from the range it had when the drag began.
    static func dragged(_ part: PlotRegionPart, from original: ClosedRange<Double>, by delta: Double, style: PlotRegionStyle) -> ClosedRange<Double> {
        let bounds = style.bounds ?? (-Double.infinity)...Double.infinity
        func snap(_ v: Double) -> Double { style.snapsToIntegers ? v.rounded() : v }
        let minLength = max(style.minLength, 0)
        switch part {
        case .start:
            let low = min(max(snap(original.lowerBound + delta), bounds.lowerBound), original.upperBound - minLength)
            return low...original.upperBound
        case .end:
            let high = max(min(snap(original.upperBound + delta), bounds.upperBound), original.lowerBound + minLength)
            return original.lowerBound...high
        case .move:
            let length = original.upperBound - original.lowerBound
            let low = min(max(snap(original.lowerBound + delta), bounds.lowerBound), bounds.upperBound - length)
            return low...(low + length)
        }
    }
}

/// What the drawing needs of a region.
struct PlotRegionDraw {
    var range: ClosedRange<Double>
    var style: PlotRegionStyle
}

extension PlotDrawing {
    /// The dimming outside the region, its dotted edges, its bar and its handles.
    func drawRegion(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ palette: PlotPalette) {
        guard let region else { return }
        let color = region.style.color
        let lo = t.x(region.range.lowerBound), hi = t.x(region.range.upperBound)
        let dim = palette.isDark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
        if lo > plot.minX { ctx.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: min(lo, plot.maxX) - plot.minX, height: plot.height)), with: .color(dim)) }
        if hi < plot.maxX {
            let left = max(hi, plot.minX)
            ctx.fill(Path(CGRect(x: left, y: plot.minY, width: plot.maxX - left, height: plot.height)), with: .color(dim))
        }
        // The bar over the region: the part that slides it.
        let barLeft = max(lo, plot.minX), barRight = min(hi, plot.maxX)
        if barRight > barLeft {
            let bar = CGRect(x: barLeft, y: plot.minY, width: barRight - barLeft, height: PlotRegionMath.barHeight)
            ctx.fill(Path(bar), with: .color(color.opacity(0.30)))
            if !region.style.name.isEmpty, bar.width > 70 {
                ctx.draw(ctx.resolve(Text(verbatim: region.style.name).font(.system(size: 10, weight: .semibold)).foregroundColor(palette.text)),
                         at: CGPoint(x: bar.midX, y: bar.midY), anchor: .center)
            }
        }
        // The dotted edges and the grips of the handles.
        for (x, isStart) in [(lo, true), (hi, false)] where x >= plot.minX - 1 && x <= plot.maxX + 1 {
            var line = Path(); line.move(to: CGPoint(x: x, y: plot.minY)); line.addLine(to: CGPoint(x: x, y: plot.maxY))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
            let grip = CGRect(x: x - 3.5, y: plot.minY + 1, width: 7, height: PlotRegionMath.barHeight - 2)
            ctx.fill(Path(roundedRect: grip, cornerRadius: 2.5), with: .color(color))
            var ridge = Path()
            ridge.move(to: CGPoint(x: x, y: grip.minY + 3)); ridge.addLine(to: CGPoint(x: x, y: grip.maxY - 3))
            ctx.stroke(ridge, with: .color(.white.opacity(0.85)), lineWidth: 1)
            _ = isStart
        }
    }
}
