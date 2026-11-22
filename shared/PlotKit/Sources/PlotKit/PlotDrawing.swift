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
}

/// The buffers of the columns, kept from one image to the next so that drawing allocates nothing.
final class EnvelopeCache {
    var envelope = Envelope()
}

/// A mark of the measure mode: two points of the view.
struct PlotMeasure: Equatable {
    var a: CGPoint
    var b: CGPoint
}

/// What is drawn: the axes and their grid, the signal (as the envelope of its columns, or as stems when the samples are far
/// enough apart to be seen), the crosshair with its readouts, the box of a zoom and the measure.
struct PlotDrawing {
    var signal: PlotSignal
    var viewport: PlotViewport
    var sampleRate: Double?
    var amplitude: AmplitudeScale
    var palette: PlotPalette
    var scale: CGFloat
    var hover: CGPoint?
    var box: PlotMeasure?
    var measure: PlotMeasure?
    var labels: PlotLabels

    /// Pixels between two samples, from which the samples are drawn one by one.
    static let stemThreshold: CGFloat = 7
    /// From this many pixels between two samples, the samples are joined by a line (below it, the columns hold several).
    static let lineThreshold: CGFloat = 1

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
            for (i, tick) in x.set.ticks.enumerated() where tick.isMajor == (pass == 1) {
                _ = i
                let px = crisp(t.x(tick.value * x.toSamples))
                var p = Path(); p.move(to: CGPoint(x: px, y: plot.minY)); p.addLine(to: CGPoint(x: px, y: plot.maxY))
                context.stroke(p, with: .color(tick.isMajor ? palette.gridMajor : palette.gridMinor), lineWidth: line)
            }
            for tick in yTicks.ticks where tick.isMajor == (pass == 1) {
                let py = crisp(t.y(tick.value))
                var p = Path(); p.move(to: CGPoint(x: plot.minX, y: py)); p.addLine(to: CGPoint(x: plot.maxX, y: py))
                context.stroke(p, with: .color(tick.isMajor ? palette.gridMajor : palette.gridMinor), lineWidth: line)
            }
        }

        // The signal, clipped to the plot.
        context.drawLayer { layer in
            layer.clip(to: Path(plot))
            if !amplitude.isDecibels, viewport.y.range.contains(0) {
                let y0 = crisp(t.y(0))
                var z = Path(); z.move(to: CGPoint(x: plot.minX, y: y0)); z.addLine(to: CGPoint(x: plot.maxX, y: y0))
                layer.stroke(z, with: .color(palette.zero), lineWidth: line)
            }
            drawSignal(&layer, t, plot, cache)
            if let box { drawBox(&layer, box) }
            if let measure { drawMeasure(&layer, measure, t) }
        }

        // Axes: baseline, ticks, labels.
        var frame = Path()
        frame.move(to: CGPoint(x: plot.minX, y: crisp(plot.maxY))); frame.addLine(to: CGPoint(x: plot.maxX, y: crisp(plot.maxY)))
        frame.move(to: CGPoint(x: crisp(plot.minX), y: plot.minY)); frame.addLine(to: CGPoint(x: crisp(plot.minX), y: plot.maxY))
        context.stroke(frame, with: .color(palette.axis), lineWidth: line)

        // A crosshair puts a flag on each axis: the labels under it are left out.
        let crosshair = crosshairPoint(t, plot)
        var lastRight = -CGFloat.infinity
        for (i, tick) in x.set.ticks.enumerated() {
            let px = crisp(t.x(tick.value * x.toSamples))
            var m = Path(); m.move(to: CGPoint(x: px, y: plot.maxY)); m.addLine(to: CGPoint(x: px, y: plot.maxY + (tick.isMajor ? 5 : 3)))
            context.stroke(m, with: .color(palette.axis), lineWidth: line)
            guard tick.isLabelled, !x.labels.texts[i].isEmpty else { continue }
            if let c = crosshair, abs(px - c.point.x) < 54 { continue }
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
            if let c = crosshair, abs(py - c.point.y) < 14 { continue }
            let text = context.resolve(Text(verbatim: yLabels.texts[i]).font(font()).foregroundColor(palette.text))
            let h = text.measure(in: CGSize(width: 200, height: 30)).height
            if py - h / 2 > lastBottom + 2 {
                context.draw(text, at: CGPoint(x: plot.minX - 9, y: py), anchor: .trailing)
                lastBottom = py + h / 2
            }
        }
        // The units, once on each axis.
        let xUnit = x.labels.unit.isEmpty ? labels.samples : x.labels.unit
        context.draw(context.resolve(Text(verbatim: xUnit).font(font(10.5, weight: .semibold)).foregroundColor(palette.text)),
                     at: CGPoint(x: plot.midX, y: size.height - 6), anchor: .bottom)
        if !amplitude.unit.isEmpty {
            var rotated = context
            rotated.translateBy(x: 12, y: plot.midY)
            rotated.rotate(by: .degrees(-90))
            rotated.draw(rotated.resolve(Text(verbatim: amplitude.unit).font(font(10.5, weight: .semibold)).foregroundColor(palette.text)), at: .zero, anchor: .center)
        }

        if let crosshair { drawCrosshair(&context, crosshair, t, plot) }
    }

    /// Where the crosshair is: under the pointer, or on the nearest sample when the samples can be told apart. The labels of the
    /// axes that it covers are left out, so this is worked out once for the labels and the crosshair.
    private struct Crosshair {
        var point: CGPoint
        /// The sample it is on, when it is on one.
        var index: Int?
    }

    private func crosshairPoint(_ t: PlotTransform, _ plot: CGRect) -> Crosshair? {
        guard let hover, plot.contains(hover), box == nil else { return nil }
        let span = viewport.x.range.upperBound - viewport.x.range.lowerBound
        let snapped = span > 0 && plot.width / CGFloat(span) >= Self.lineThreshold
        let i = Int(t.xValue(hover.x).rounded())
        if snapped, i >= 0, i < signal.count {
            return Crosshair(point: CGPoint(x: t.x(Double(i)), y: t.y(amplitude.value(signal.sample(at: i)))), index: i)
        }
        return Crosshair(point: hover, index: nil)
    }

    // MARK: The axes

    private struct XTicks { var set: TickSet; var labels: AxisLabels; var toSamples: Double }

    /// The graduations of the horizontal axis: in time when the sample rate is known, in whole samples otherwise.
    private func xAxisTicks(width: CGFloat) -> XTicks {
        let target = max(2, Int(width / 100))
        let r = viewport.x.range
        let logarithmic = viewport.x.scale == .logarithmic
        if let sr = sampleRate, sr > 0 {
            let seconds = (r.lowerBound / sr)...(r.upperBound / sr)
            let set = logarithmic ? Ticks.logarithmic(in: seconds) : Ticks.linear(in: seconds, approximately: target)
            return XTicks(set: set, labels: TickLabels.labels(for: set, unit: "s"), toSamples: sr)
        }
        let set = logarithmic ? Ticks.logarithmic(in: r) : Ticks.linear(in: r, approximately: target, integersOnly: true)
        return XTicks(set: set, labels: TickLabels.labels(for: set), toSamples: 1)
    }

    // MARK: The signal

    private func drawSignal(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ cache: EnvelopeCache) {
        let range = viewport.x.range
        let span = range.upperBound - range.lowerBound
        guard span > 0, signal.count > 0 else { return }
        let pixelsPerSample = plot.width / CGFloat(span)
        if pixelsPerSample >= Self.stemThreshold {
            drawStems(&ctx, t, plot, pixelsPerSample)
        } else if pixelsPerSample >= Self.lineThreshold {
            drawSampleLine(&ctx, t, plot)
        } else {
            drawEnvelope(&ctx, t, plot, cache)
        }
    }

    /// The samples joined by a line, with the area to the zero line (or to the floor in decibels) filled: what a signal looks
    /// like between the envelope, where a column holds many samples, and the stems, where each sample can be seen alone.
    private func drawSampleLine(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect) {
        let range = viewport.x.range
        let first = max(0, Int(floor(range.lowerBound)) - 1), last = min(signal.count - 1, Int(ceil(range.upperBound)) + 1)
        guard first < last else { return }
        var line = Path()
        for i in first...last {
            let p = CGPoint(x: t.x(Double(i)), y: t.y(amplitude.value(signal.sample(at: i))))
            if i == first { line.move(to: p) } else { line.addLine(to: p) }
        }
        let baseline = amplitude.isDecibels ? plot.maxY + 2 : t.y(0)
        var area = line
        area.addLine(to: CGPoint(x: t.x(Double(last)), y: baseline))
        area.addLine(to: CGPoint(x: t.x(Double(first)), y: baseline))
        area.closeSubpath()
        if amplitude.isDecibels {
            ctx.fill(area, with: .linearGradient(Gradient(colors: [palette.accent.opacity(0.5), palette.accent.opacity(0.03)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        } else {
            let zero = min(1, max(0, (t.y(0) - plot.minY) / plot.height))
            ctx.fill(area, with: .linearGradient(
                Gradient(stops: [.init(color: palette.accent.opacity(0.5), location: 0), .init(color: palette.accent.opacity(0.08), location: zero),
                                 .init(color: palette.accent.opacity(0.5), location: 1)]),
                startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        }
        ctx.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    /// One sample per stem with a head, as an audio editor shows them when it is zoomed in.
    private func drawStems(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ pixelsPerSample: CGFloat) {
        let range = viewport.x.range
        let first = max(0, Int(floor(range.lowerBound)) - 1), last = min(signal.count - 1, Int(ceil(range.upperBound)) + 1)
        guard first <= last else { return }
        let baseline = amplitude.isDecibels ? plot.maxY : t.y(0)
        let radius: CGFloat = pixelsPerSample >= 16 ? 3.6 : 3
        var stems = Path(), heads = Path()
        for i in first...last {
            let px = t.x(Double(i)), py = t.y(amplitude.value(signal.sample(at: i)))
            stems.move(to: CGPoint(x: px, y: baseline)); stems.addLine(to: CGPoint(x: px, y: py))
            heads.addEllipse(in: CGRect(x: px - radius, y: py - radius, width: 2 * radius, height: 2 * radius))
        }
        ctx.stroke(stems, with: .color(palette.accent.opacity(0.75)), lineWidth: 1.3)
        ctx.fill(heads, with: .color(palette.accent))
        ctx.stroke(heads, with: .color(palette.isDark ? Color.white.opacity(0.55) : Color.white.opacity(0.9)), lineWidth: 0.8)
    }

    /// The envelope of the columns: the band between the smallest and the largest sample of each (or the line of the largest
    /// magnitude in decibels), with a gradient, and a stroke on its edges.
    private func drawEnvelope(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ cache: EnvelopeCache) {
        let columns = min(4000, max(2, Int(plot.width * scale)))
        let range = viewport.x.range
        signal.envelope(from: range.lowerBound, to: range.upperBound, columns: columns, into: &cache.envelope)
        let e = cache.envelope
        guard !e.valid.isEmpty else { return }
        let step = plot.width / CGFloat(columns)
        func px(_ c: Int) -> CGFloat { plot.minX + (CGFloat(c) + 0.5) * step }

        if amplitude.isDecibels {
            var line = Path()
            for c in e.valid {
                let p = CGPoint(x: px(c), y: t.y(amplitude.value(max(abs(e.lo[c]), abs(e.hi[c])))))
                if c == e.valid.lowerBound { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: px(e.valid.upperBound - 1), y: plot.maxY + 2))
            area.addLine(to: CGPoint(x: px(e.valid.lowerBound), y: plot.maxY + 2))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [palette.accent.opacity(0.5), palette.accent.opacity(0.03)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            return
        }

        var top = Path(), bottom = Path(), band = Path()
        for c in e.valid {
            var yHi = t.y(Double(e.hi[c])), yLo = t.y(Double(e.lo[c]))
            if yLo - yHi < 1 { let mid = (yHi + yLo) / 2; yHi = mid - 0.5; yLo = mid + 0.5 }
            let p = CGPoint(x: px(c), y: yHi)
            if c == e.valid.lowerBound { top.move(to: p); band.move(to: p) } else { top.addLine(to: p); band.addLine(to: p) }
        }
        for c in e.valid.reversed() {
            var yHi = t.y(Double(e.hi[c])), yLo = t.y(Double(e.lo[c]))
            if yLo - yHi < 1 { let mid = (yHi + yLo) / 2; yHi = mid - 0.5; yLo = mid + 0.5 }
            let p = CGPoint(x: px(c), y: yLo)
            band.addLine(to: p)
            if c == e.valid.upperBound - 1 { bottom.move(to: p) } else { bottom.addLine(to: p) }
        }
        band.closeSubpath()
        // Strong at the extremes, light around the zero line.
        let zero = min(1, max(0, (t.y(0) - plot.minY) / plot.height))
        ctx.fill(band, with: .linearGradient(
            Gradient(stops: [.init(color: palette.accent.opacity(0.55), location: 0), .init(color: palette.accent.opacity(0.10), location: zero),
                             .init(color: palette.accent.opacity(0.55), location: 1)]),
            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        ctx.stroke(top, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
        ctx.stroke(bottom, with: .color(palette.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
    }

    // MARK: Interaction marks

    private func drawBox(_ ctx: inout GraphicsContext, _ box: PlotMeasure) {
        let r = CGRect(x: min(box.a.x, box.b.x), y: min(box.a.y, box.b.y), width: abs(box.a.x - box.b.x), height: abs(box.a.y - box.b.y))
        ctx.fill(Path(r), with: .color(palette.accent.opacity(0.14)))
        ctx.stroke(Path(r), with: .color(palette.accent), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func drawMeasure(_ ctx: inout GraphicsContext, _ m: PlotMeasure, _ t: PlotTransform) {
        var line = Path(); line.move(to: m.a); line.addLine(to: m.b)
        ctx.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        for p in [m.a, m.b] {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(palette.accent))
        }
        let dx = t.xValue(m.b.x) - t.xValue(m.a.x), dy = t.yValue(m.b.y) - t.yValue(m.a.y)
        var lines: [String] = []
        if let sr = sampleRate, sr > 0 {
            lines.append("Δt = " + TickLabels.engineering(dx / sr, unit: "s") + "  (\(Int(dx.rounded())) n)")
            if dx != 0 { lines.append("1/Δt = " + TickLabels.engineering(abs(sr / dx), unit: "Hz")) }
        } else {
            lines.append("Δn = \(Int(dx.rounded()))")
        }
        lines.append("Δ = " + (amplitude.isDecibels ? TickLabels.number(dy, decimals: 1) + " dB" : TickLabels.number(dy, decimals: 4)))
        drawTooltip(&ctx, lines, near: CGPoint(x: (m.a.x + m.b.x) / 2, y: (m.a.y + m.b.y) / 2), in: t.rect)
    }

    private func drawCrosshair(_ ctx: inout GraphicsContext, _ cross: Crosshair, _ t: PlotTransform, _ plot: CGRect) {
        let xv = t.xValue(cross.point.x)
        let index = cross.index
        let x = cross.point.x, y = cross.point.y
        guard plot.insetBy(dx: -1, dy: -1).contains(cross.point) || index == nil else { return }
        let dash = StrokeStyle(lineWidth: 1 / scale, dash: [3, 3])
        var v = Path(); v.move(to: CGPoint(x: x, y: plot.minY)); v.addLine(to: CGPoint(x: x, y: plot.maxY))
        var h = Path(); h.move(to: CGPoint(x: plot.minX, y: y)); h.addLine(to: CGPoint(x: plot.maxX, y: y))
        ctx.stroke(v, with: .color(palette.spike), style: dash)
        ctx.stroke(h, with: .color(palette.spike), style: dash)

        // What is under the pointer: flags on the two axes, and a card near it.
        let samplePosition = index.map(Double.init) ?? xv
        let xText = sampleRate.map { TickLabels.engineering(samplePosition / $0, unit: "s") } ?? "n = " + String(Int(samplePosition.rounded()))
        let yValue = index.map { amplitude.value(signal.sample(at: $0)) } ?? t.yValue(y)
        let yText = amplitude.isDecibels ? TickLabels.number(yValue, decimals: 1) + " dB" : TickLabels.number(yValue, decimals: abs(yValue) < 0.1 ? 4 : 3)
        flag(&ctx, xText, at: CGPoint(x: x, y: plot.maxY + 20), anchor: .center)
        flag(&ctx, yText, at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
        if let i = index {
            var lines = [String]()
            if let sr = sampleRate, sr > 0 { lines.append("t = " + TickLabels.engineering(Double(i) / sr, unit: "s")) }
            lines.append("n = \(i)")
            let v = Double(signal.sample(at: i))
            lines.append(TickLabels.number(v, decimals: 4) + "  (" + (v == 0 ? "−∞" : TickLabels.number(20 * log10(abs(v)), decimals: 1)) + " dB)")
            ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)), with: .color(palette.accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)), with: .color(.white), lineWidth: 1.5)
            drawTooltip(&ctx, lines, near: CGPoint(x: x + 16, y: y - 18), in: plot)
        }
    }

    private func flag(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, anchor: UnitPoint) {
        let resolved = ctx.resolve(Text(verbatim: text).font(font(10.5, weight: .semibold)).foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: 300, height: 30))
        let box = CGRect(x: p.x - size.width * anchor.x - 6, y: p.y - size.height * anchor.y - 2, width: size.width + 12, height: size.height + 4)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(palette.accent))
        ctx.draw(resolved, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    private func drawTooltip(_ ctx: inout GraphicsContext, _ lines: [String], near p: CGPoint, in area: CGRect) {
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
        ctx.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color(palette.accent.opacity(0.7)), lineWidth: 1)
        for (i, r) in resolved.enumerated() {
            ctx.draw(r, at: CGPoint(x: box.minX + 10, y: box.minY + 7 + lineHeight * CGFloat(i)), anchor: .topLeading)
        }
    }
}
