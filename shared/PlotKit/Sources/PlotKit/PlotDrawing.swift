// SPDX-License-Identifier: MIT

import SwiftUI

/// The colours of a plot for the light and the dark appearance.
struct PlotPalette {
    var accent: Color
    var isDark: Bool

    var background: Color { isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.028) }
    var gridMinor: Color { isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.06) }
    var gridMajor: Color { isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.14) }
    var zero: Color { isDark ? Color.white.opacity(0.30) : Color.black.opacity(0.32) }
    var axis: Color { isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.30) }
    var text: Color { isDark ? Color.white.opacity(0.66) : Color.black.opacity(0.66) }
    var spike: Color { isDark ? Color.white.opacity(0.42) : Color.black.opacity(0.42) }
    var tooltip: Color { isDark ? Color(white: 0.12, opacity: 0.94) : Color(white: 1, opacity: 0.95) }
    var tooltipText: Color { isDark ? .white : .black }
    /// The colour of the i-th trace (a channel, a curve): the accent first, then colours that are neither the box's nor the measure's.
    func trace(_ i: Int, _ custom: Color? = nil) -> Color {
        if let custom { return custom }
        let others: [Color] = [Color(red: 0.25, green: 0.78, blue: 0.68), Color(red: 1.0, green: 0.45, blue: 0.62), Color(red: 0.48, green: 0.84, blue: 0.36)]
        return i == 0 ? accent : others[(i - 1) % others.count]
    }

    /// The box of a zoom has a colour of its own too: neither the signal's nor the measure's.
    var box: Color { isDark ? Color(red: 0.32, green: 0.72, blue: 1.0) : Color(red: 0.0, green: 0.46, blue: 0.86) }
    /// The measure has a colour of its own, to tell it from the signal.
    var measure: Color { isDark ? Color(red: 1.0, green: 0.66, blue: 0.22) : Color(red: 0.86, green: 0.42, blue: 0.0) }
}

/// The buffers of the columns, kept from one image to the next so that drawing allocates nothing.
final class EnvelopeCache {
    var envelope = Envelope()
}

/// A box drawn with the mouse: two points of the view.
struct PlotMeasure: Equatable {
    var a: CGPoint
    var b: CGPoint
}

/// A measure between two points of the data, so that it follows the data when the view moves.
struct PlotSegment: Equatable {
    var x0: Double, y0: Double
    var x1: Double, y1: Double
}

/// What is drawn that every plot has: the axes with their grid and labels, the box of a zoom, the measure, and the crosshair
/// with its flags and its card. The data themselves are drawn by the content of the plot.
struct PlotDrawing {
    var content: any PlotContent
    var viewport: PlotViewport
    var palette: PlotPalette
    var scale: CGFloat
    var hover: CGPoint?
    var box: PlotMeasure?
    var measure: PlotSegment?

    private func font(_ size: CGFloat = 10.5, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight).monospacedDigit() }

    /// A position on a pixel, so that a line one pixel wide is sharp.
    private func crisp(_ v: CGFloat) -> CGFloat { (v * scale).rounded(.down) / scale + 0.5 / scale }

    func draw(_ context: inout GraphicsContext, size: CGSize, cache: EnvelopeCache) {
        let layout = PlotLayout(size: size)
        let plot = layout.plot
        guard plot.width > 40, plot.height > 30 else { return }
        let t = PlotTransform(viewport: viewport, rect: plot)
        let line = 1 / scale

        context.fill(Path(roundedRect: plot, cornerRadius: 3), with: .color(palette.background))

        // The graduations.
        let x = xAxisTicks(width: plot.width)
        let yTicks = viewport.y.scale == .logarithmic ? Ticks.logarithmic(in: viewport.y.range)
                                                       : Ticks.linear(in: viewport.y.range, approximately: max(2, Int(plot.height / 46)))
        let yLabels = TickLabels.labels(for: yTicks)

        // Grid, minor first.
        for pass in 0..<2 {
            for tick in x.set.ticks where tick.isMajor == (pass == 1) {
                let px = crisp(t.x(tick.value * x.divisor))
                var p = Path(); p.move(to: CGPoint(x: px, y: plot.minY)); p.addLine(to: CGPoint(x: px, y: plot.maxY))
                context.stroke(p, with: .color(tick.isMajor ? palette.gridMajor : palette.gridMinor), lineWidth: line)
            }
            for tick in yTicks.ticks where tick.isMajor == (pass == 1) {
                let py = crisp(t.y(tick.value))
                var p = Path(); p.move(to: CGPoint(x: plot.minX, y: py)); p.addLine(to: CGPoint(x: plot.maxX, y: py))
                context.stroke(p, with: .color(tick.isMajor ? palette.gridMajor : palette.gridMinor), lineWidth: line)
            }
        }

        // The data, clipped to the plot.
        context.drawLayer { layer in
            layer.clip(to: Path(plot))
            if content.hasZeroLine, viewport.y.scale == .linear, viewport.y.range.contains(0) {
                let y0 = crisp(t.y(0))
                var z = Path(); z.move(to: CGPoint(x: plot.minX, y: y0)); z.addLine(to: CGPoint(x: plot.maxX, y: y0))
                layer.stroke(z, with: .color(palette.zero), lineWidth: line)
            }
            content.drawData(&layer, t, palette, scale, cache)
            if let box { drawBox(&layer, box) }
            if let measure { drawMeasure(&layer, measure, t) }
        }

        // Axes: baseline, ticks, labels.
        var frame = Path()
        frame.move(to: CGPoint(x: plot.minX, y: crisp(plot.maxY))); frame.addLine(to: CGPoint(x: plot.maxX, y: crisp(plot.maxY)))
        frame.move(to: CGPoint(x: crisp(plot.minX), y: plot.minY)); frame.addLine(to: CGPoint(x: crisp(plot.minX), y: plot.maxY))
        context.stroke(frame, with: .color(palette.axis), lineWidth: line)

        // A crosshair puts a flag on each axis: the labels under it are left out.
        let probe = crosshair(t, plot)
        var lastRight = -CGFloat.infinity
        for (i, tick) in x.set.ticks.enumerated() {
            let px = crisp(t.x(tick.value * x.divisor))
            var m = Path(); m.move(to: CGPoint(x: px, y: plot.maxY)); m.addLine(to: CGPoint(x: px, y: plot.maxY + (tick.isMajor ? 5 : 3)))
            context.stroke(m, with: .color(palette.axis), lineWidth: line)
            guard tick.isLabelled, !x.labels.texts[i].isEmpty else { continue }
            if let c = probe, abs(px - c.point.x) < 54 { continue }
            let text = context.resolve(Text(verbatim: x.labels.texts[i]).font(font()).foregroundColor(palette.text))
            let w = text.measure(in: CGSize(width: 200, height: 30)).width
            if px - w / 2 > lastRight + 8 {
                context.draw(text, at: CGPoint(x: px, y: plot.maxY + 8), anchor: .top)
                lastRight = px + w / 2
            }
        }
        var lastBottom = -CGFloat.infinity
        for (i, tick) in yTicks.ticks.enumerated().reversed() {
            let py = crisp(t.y(tick.value))
            var m = Path(); m.move(to: CGPoint(x: plot.minX - (tick.isMajor ? 5 : 3), y: py)); m.addLine(to: CGPoint(x: plot.minX, y: py))
            context.stroke(m, with: .color(palette.axis), lineWidth: line)
            guard tick.isLabelled, !yLabels.texts[i].isEmpty else { continue }
            if let c = probe, abs(py - c.point.y) < 14 { continue }
            let text = context.resolve(Text(verbatim: yLabels.texts[i]).font(font()).foregroundColor(palette.text))
            let h = text.measure(in: CGSize(width: 200, height: 30)).height
            if py - h / 2 > lastBottom + 2 {
                context.draw(text, at: CGPoint(x: plot.minX - 9, y: py), anchor: .trailing)
                lastBottom = py + h / 2
            }
        }
        // The units, once on each axis.
        let xUnit = x.labels.unit.isEmpty ? content.xCaption : x.labels.unit
        context.draw(context.resolve(Text(verbatim: xUnit).font(font(10.5, weight: .semibold)).foregroundColor(palette.text)),
                     at: CGPoint(x: plot.midX, y: size.height - 6), anchor: .bottom)
        if !content.yUnit.isEmpty {
            var rotated = context
            rotated.translateBy(x: 12, y: plot.midY)
            rotated.rotate(by: .degrees(-90))
            rotated.draw(rotated.resolve(Text(verbatim: content.yUnit).font(font(10.5, weight: .semibold)).foregroundColor(palette.text)), at: .zero, anchor: .center)
        }

        if let probe { drawCrosshair(&context, probe, plot) }
    }

    private func crosshair(_ t: PlotTransform, _ plot: CGRect) -> PlotProbe? {
        guard let hover, plot.contains(hover), box == nil else { return nil }
        return content.probe(at: hover, t)
    }

    // MARK: The axes

    private struct XTicks { var set: TickSet; var labels: AxisLabels; var divisor: Double }

    /// The graduations of the horizontal axis, in the units the content gives (seconds for a time axis in samples).
    private func xAxisTicks(width: CGFloat) -> XTicks {
        let target = max(2, Int(width / 100))
        let r = viewport.x.range
        let d = content.xDivisor > 0 ? content.xDivisor : 1
        let shown = (r.lowerBound / d)...(r.upperBound / d)
        let set = viewport.x.scale == .logarithmic ? Ticks.logarithmic(in: shown)
                                                   : Ticks.linear(in: shown, approximately: target, integersOnly: content.xIntegers && d == 1)
        return XTicks(set: set, labels: TickLabels.labels(for: set, unit: content.xUnit), divisor: d)
    }

    // MARK: Interaction marks

    private func drawBox(_ ctx: inout GraphicsContext, _ box: PlotMeasure) {
        let r = CGRect(x: min(box.a.x, box.b.x), y: min(box.a.y, box.b.y), width: abs(box.a.x - box.b.x), height: abs(box.a.y - box.b.y))
        ctx.fill(Path(r), with: .color(palette.box.opacity(0.16)))
        ctx.stroke(Path(r), with: .color(palette.box), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
    }

    private func drawMeasure(_ ctx: inout GraphicsContext, _ m: PlotSegment, _ t: PlotTransform) {
        let a = t.point(x: m.x0, y: m.y0), b = t.point(x: m.x1, y: m.y1), corner = t.point(x: m.x1, y: m.y0)
        let colour = palette.measure
        // The two parts of the difference, dotted, then the segment itself.
        var parts = Path()
        parts.move(to: a); parts.addLine(to: corner); parts.addLine(to: b)
        ctx.stroke(parts, with: .color(colour.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        var line = Path(); line.move(to: a); line.addLine(to: b)
        ctx.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        for p in [a, b] {
            let dot = Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
            ctx.fill(dot, with: .color(colour))
            ctx.stroke(dot, with: .color(palette.isDark ? .black.opacity(0.5) : .white), lineWidth: 1.2)
        }
        drawTooltip(&ctx, content.measureReadout(m), near: CGPoint(x: (a.x + b.x) / 2 + 14, y: (a.y + b.y) / 2 - 10), in: t.rect, border: colour)
    }

    private func drawCrosshair(_ ctx: inout GraphicsContext, _ probe: PlotProbe, _ plot: CGRect) {
        let x = probe.point.x, y = probe.point.y
        guard plot.insetBy(dx: -1, dy: -1).contains(probe.point) || !probe.onData else { return }
        let dash = StrokeStyle(lineWidth: 1 / scale, dash: [3, 3])
        var v = Path(); v.move(to: CGPoint(x: x, y: plot.minY)); v.addLine(to: CGPoint(x: x, y: plot.maxY))
        var h = Path(); h.move(to: CGPoint(x: plot.minX, y: y)); h.addLine(to: CGPoint(x: plot.maxX, y: y))
        ctx.stroke(v, with: .color(palette.spike), style: dash)
        ctx.stroke(h, with: .color(palette.spike), style: dash)
        let colour = palette.trace(probe.trace, probe.customColor)
        flag(&ctx, probe.xFlag, at: CGPoint(x: x, y: plot.maxY + 20), anchor: .center, colour: colour)
        flag(&ctx, probe.yFlag, at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing, colour: colour)
        if probe.onData {
            let marker = Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
            ctx.fill(marker, with: .color(colour))
            ctx.stroke(marker, with: .color(.white), lineWidth: 1.5)
            if !probe.card.isEmpty { drawTooltip(&ctx, probe.card, near: CGPoint(x: x + 16, y: y - 18), in: plot, border: colour) }
        }
    }

    private func flag(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, anchor: UnitPoint, colour: Color) {
        let resolved = ctx.resolve(Text(verbatim: text).font(font(10.5, weight: .semibold)).foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: 300, height: 30))
        let box = CGRect(x: p.x - size.width * anchor.x - 6, y: p.y - size.height * anchor.y - 2, width: size.width + 12, height: size.height + 4)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(colour))
        ctx.draw(resolved, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    private func drawTooltip(_ ctx: inout GraphicsContext, _ lines: [String], near p: CGPoint, in area: CGRect, border: Color? = nil) {
        let resolved = lines.map { ctx.resolve(Text(verbatim: $0).font(font(11)).foregroundColor(palette.tooltipText)) }
        let sizes = resolved.map { $0.measure(in: CGSize(width: 400, height: 30)) }
        let width = (sizes.map(\.width).max() ?? 0) + 20, lineHeight = (sizes.first?.height ?? 14) + 2
        let height = lineHeight * CGFloat(lines.count) + 14
        var origin = p
        if origin.x + width > area.maxX { origin.x = p.x - width - 32 }
        if origin.y + height > area.maxY { origin.y = area.maxY - height - 4 }
        origin.x = max(area.minX + 4, origin.x); origin.y = max(area.minY + 4, origin.y)
        let box = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        ctx.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(palette.tooltip))
        ctx.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color((border ?? palette.accent).opacity(0.75)), lineWidth: 1)
        for (i, r) in resolved.enumerated() {
            ctx.draw(r, at: CGPoint(x: box.minX + 10, y: box.minY + 7 + lineHeight * CGFloat(i)), anchor: .topLeading)
        }
    }
}
