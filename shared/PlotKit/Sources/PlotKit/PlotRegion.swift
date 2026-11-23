// SPDX-License-Identifier: MIT

import SwiftUI

/// How an editable region looks and what it may be.
public struct PlotRegionStyle {
    public var color: Color
    /// The colour in a light appearance, when `color` (a light one, for instance) would not show there.
    public var lightColor: Color?
    /// The smallest length, in the units of the horizontal axis.
    public var minLength: Double
    /// What the region cannot leave, in the units of the horizontal axis; `nil` for no limit.
    public var bounds: ClosedRange<Double>?
    /// The ends are whole numbers (sample numbers).
    public var snapsToIntegers: Bool
    /// Written next to the region when it is wide enough.
    public var name: String
    /// What is written in the bubbles that follow a slider while it is dragged: a position or a length, in the units of the axis (the sample
    /// number, and the time it makes, for instance). A whole number when there is none.
    public var format: (@Sendable (Double) -> String)?

    public init(color: Color = .accentColor, minLength: Double = 1, bounds: ClosedRange<Double>? = nil, snapsToIntegers: Bool = true, name: String = "",
                format: (@Sendable (Double) -> String)? = nil, lightColor: Color? = nil) {
        self.color = color
        self.lightColor = lightColor
        self.minLength = minLength
        self.bounds = bounds
        self.snapsToIntegers = snapsToIntegers
        self.name = name
        self.format = format
    }

    func text(_ value: Double) -> String { format?(value) ?? String(Int(value.rounded())) }

    func color(isDark: Bool) -> Color { isDark ? color : (lightColor ?? color) }

    /// What is written on the colour (the bubbles, the knobs): dark on a light colour, white on a dark one.
    func onColor(isDark: Bool) -> Color { Self.isLight(color(isDark: isDark)) ? Color.black.opacity(0.78) : .white }

    static func isLight(_ color: Color) -> Bool {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.62
    }
}

/// A range of the horizontal axis that the person can change in the plot: two sliders on a rail under the plot, as the levels of the color
/// adjustment of Preview have (drag a knob to move an end, the part of the rail between them to slide the whole range), and dotted lines
/// across the plot. What is outside is dimmed. While a slider is dragged, bubbles say where the ends are and how long the range is. The range
/// is updated while the drag goes on; `onCommit` is called when it ends, so that an application that keeps an undo history records one change.
public struct PlotRegionEditor {
    public var range: Binding<ClosedRange<Double>>
    public var style: PlotRegionStyle
    public var onCommit: () -> Void
    /// A part to show as if it were being dragged (the bubbles that tell the positions), for previews and tests.
    public var previewDragging: PlotRegionPart?

    public init(range: Binding<ClosedRange<Double>>, style: PlotRegionStyle = PlotRegionStyle(), previewDragging: PlotRegionPart? = nil,
                onCommit: @escaping () -> Void = {}) {
        self.range = range
        self.style = style
        self.previewDragging = previewDragging
        self.onCommit = onCommit
    }
}

/// What a drag on a region moves.
public enum PlotRegionPart: Equatable, Sendable { case start, end, move }

/// Where the sliders are and what a drag does to the range: apart from the view so that it can be tested.
enum PlotRegionMath {
    /// How near the pointer must be to an edge of the region in the plot to take it, in points.
    static let tolerance: CGFloat = 6
    /// The height of the rail of the sliders, under the plot.
    static let railHeight: CGFloat = 28
    /// How near the pointer must be to a knob on the rail to take it, in points.
    static let knobHit: CGFloat = 11

    /// The part of the region under a point of the view, given where its edges are on the screen (`lo` and `hi`).
    static func part(at p: CGPoint, lo: CGFloat, hi: CGFloat, plot: CGRect, rail: CGRect? = nil) -> PlotRegionPart? {
        // The rail first: the knobs, then the part of the rail between them.
        if let rail, !rail.isEmpty, p.y >= rail.minY - 2, p.y <= rail.maxY + 2 {
            let nearLo = abs(p.x - lo) <= knobHit, nearHi = abs(p.x - hi) <= knobHit
            if nearLo || nearHi {
                if nearLo && nearHi { return p.x < (lo + hi) / 2 ? .start : .end }
                return nearLo ? .start : .end
            }
            if p.x > lo, p.x < hi { return .move }
            return nil
        }
        guard p.y >= plot.minY, p.y <= plot.maxY, p.x >= plot.minX - tolerance, p.x <= plot.maxX + tolerance else { return nil }
        let nearLo = abs(p.x - lo) <= tolerance, nearHi = abs(p.x - hi) <= tolerance
        if nearLo || nearHi {
            if nearLo && nearHi { return p.x < (lo + hi) / 2 ? .start : .end }
            return nearLo ? .start : .end
        }
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
    /// The part that is being dragged, if one is: bubbles tell then where the ends are.
    var dragging: PlotRegionPart?
}

extension PlotDrawing {
    /// In the plot: the dimming outside the region, its dotted edges and its name.
    func drawRegion(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ palette: PlotPalette) {
        guard let region else { return }
        let color = region.style.color(isDark: palette.isDark)
        let lo = t.x(region.range.lowerBound), hi = t.x(region.range.upperBound)
        let dim = palette.isDark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
        if lo > plot.minX { ctx.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: min(lo, plot.maxX) - plot.minX, height: plot.height)), with: .color(dim)) }
        if hi < plot.maxX {
            let left = max(hi, plot.minX)
            ctx.fill(Path(CGRect(x: left, y: plot.minY, width: plot.maxX - left, height: plot.height)), with: .color(dim))
        }
        for x in [lo, hi] where x >= plot.minX - 1 && x <= plot.maxX + 1 {
            var line = Path(); line.move(to: CGPoint(x: x, y: plot.minY)); line.addLine(to: CGPoint(x: x, y: plot.maxY))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
        }
    }

    /// Under the plot: the rail, the part of it that is the region, the two knobs, and the bubbles of a drag.
    func drawRail(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ rail: CGRect, _ palette: PlotPalette) {
        guard let region, rail.height > 0 else { return }
        let color = region.style.color(isDark: palette.isDark)
        let ink = region.style.onColor(isDark: palette.isDark)
        let lo = t.x(region.range.lowerBound), hi = t.x(region.range.upperBound)
        let trackY = rail.midY + 2, trackHeight: CGFloat = 4
        let track = CGRect(x: plot.minX, y: trackY - trackHeight / 2, width: plot.width, height: trackHeight)
        ctx.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(palette.gridMajor))
        // The part of the rail that is the region: the one a drag slides.
        let a = min(max(lo, plot.minX), plot.maxX), b = min(max(hi, plot.minX), plot.maxX)
        if b > a { ctx.fill(Path(roundedRect: CGRect(x: a, y: trackY - 3, width: b - a, height: 6), cornerRadius: 3), with: .color(color.opacity(region.dragging == .move ? 1 : 0.8))) }
        for (x, part) in [(lo, PlotRegionPart.start), (hi, PlotRegionPart.end)] where x >= plot.minX - 1 && x <= plot.maxX + 1 {
            knob(&ctx, at: x, in: rail, color: color, ink: ink, isActive: region.dragging == part)
        }
        if let dragging = region.dragging {
            // Where the ends are, in the units the .conf file uses, and how long the region is.
            let bubbleY = plot.maxY - 8
            flag(&ctx, region.style.text(region.range.lowerBound), at: CGPoint(x: lo - 4, y: bubbleY), anchor: .bottomTrailing, colour: color, text: ink)
            flag(&ctx, region.style.text(region.range.upperBound), at: CGPoint(x: hi + 4, y: bubbleY), anchor: .bottomLeading, colour: color, text: ink)
            if dragging == .move || hi - lo > 150 {
                flag(&ctx, "↔ " + region.style.text(region.range.upperBound - region.range.lowerBound), at: CGPoint(x: (lo + hi) / 2, y: bubbleY - 28), anchor: .bottom, colour: color, text: ink)
            }
        }
    }

    private func knob(_ ctx: inout GraphicsContext, at x: CGFloat, in rail: CGRect, color: Color, ink: Color, isActive: Bool) {
        PlotRegionKnob.draw(&ctx, at: x, in: rail, color: color, ink: ink, isActive: isActive, scale: 1)
    }
}

/// A knob of the rail: a pentagon that points up to the plot, like the sliders of the levels of Preview, in the colour of the region, with a
/// white edge and a bar that says it is a slider. `scale` makes it smaller for a rail that is lower than the one of a plot.
enum PlotRegionKnob {
    static func draw(_ ctx: inout GraphicsContext, at x: CGFloat, in rail: CGRect, color: Color, ink: Color, isActive: Bool, scale s: CGFloat) {
        let half: CGFloat = (isActive ? 10 : 9) * s, round = 2 * s
        let tip = rail.minY + 0.5, shoulder = rail.minY + 10 * s, bottom = rail.maxY - 1
        var shape = Path()
        shape.move(to: CGPoint(x: x, y: tip))
        shape.addLine(to: CGPoint(x: x + half, y: shoulder))
        shape.addLine(to: CGPoint(x: x + half, y: bottom - round))
        shape.addQuadCurve(to: CGPoint(x: x + half - round, y: bottom), control: CGPoint(x: x + half, y: bottom))
        shape.addLine(to: CGPoint(x: x - half + round, y: bottom))
        shape.addQuadCurve(to: CGPoint(x: x - half, y: bottom - round), control: CGPoint(x: x - half, y: bottom))
        shape.addLine(to: CGPoint(x: x - half, y: shoulder))
        shape.closeSubpath()
        ctx.fill(shape.offsetBy(dx: 0, dy: 1), with: .color(.black.opacity(0.35)))
        ctx.fill(shape, with: .color(color))
        ctx.stroke(shape, with: .color(StrokeInk.edge(for: color)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        // The bar inside, as the knobs of Preview have.
        ctx.fill(Path(roundedRect: CGRect(x: x - 4.5 * s, y: bottom - 7 * s, width: 9 * s, height: 3 * s), cornerRadius: 1.5 * s), with: .color(ink))
    }
}

/// The edge of a knob: white round a dark colour, a dark line round a light one.
private enum StrokeInk {
    static func edge(for color: Color) -> Color { PlotRegionStyle.isLight(color) ? Color.black.opacity(0.35) : Color.white.opacity(0.9) }
}
