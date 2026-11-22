// SPDX-License-Identifier: MIT

import SwiftUI

/// One signal of a plot, a channel of a file for instance.
public struct PlotTrace {
    public var name: String
    public var signal: PlotSignal
    /// `nil`: a colour of the palette.
    public var color: Color?
    public init(name: String, signal: PlotSignal, color: Color? = nil) {
        self.name = name
        self.signal = signal
        self.color = color
    }
}

/// The content of a plot of signals in time: the envelope of the columns, the samples joined by a line, or the samples as stems.
/// Several traces are drawn over each other, each in its colour, without the gradient that would hide the others.
struct SignalContent: PlotContent {
    var traces: [PlotTrace]
    var sampleRate: Double?
    var amplitude: AmplitudeScale

    private var length: Int { traces.map { $0.signal.count }.max() ?? 0 }
    /// How strong the gradient under a trace is: full for one, light for several, which would hide each other.
    private var fill: Double { traces.count == 1 ? 1 : 0.22 }

    /// Pixels between two samples, from which the samples are drawn one by one.
    static let stemThreshold: CGFloat = 7
    /// From this many pixels between two samples, the samples are joined by a line (below it, the columns hold several).
    static let lineThreshold: CGFloat = 1

    var xUnit: String { sampleRate.map { $0 > 0 ? "s" : "" } ?? "" }
    var xDivisor: Double { sampleRate.flatMap { $0 > 0 ? $0 : nil } ?? 1 }
    var xIntegers: Bool { true }
    var xCaption: String { "samples" }
    var yUnit: String { amplitude.unit }
    var hasZeroLine: Bool { !amplitude.isDecibels }
    var measureKey: AnyHashable { amplitude }

    // MARK: Drawing

    func drawData(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ scale: CGFloat, _ cache: EnvelopeCache) {
        let range = t.viewport.x.range
        let span = range.upperBound - range.lowerBound
        guard span > 0, length > 0 else { return }
        let pixelsPerSample = t.rect.width / CGFloat(span)
        // The first trace is drawn last, over the others.
        for i in traces.indices.reversed() {
            let signal = traces[i].signal, colour = palette.trace(i, traces[i].color)
            if pixelsPerSample >= Self.stemThreshold {
                drawStems(&ctx, t, palette, signal, colour, pixelsPerSample)
            } else if pixelsPerSample >= Self.lineThreshold {
                drawSampleLine(&ctx, t, palette, signal, colour)
            } else {
                drawEnvelope(&ctx, t, palette, scale, cache, signal, colour)
            }
        }
    }

    /// The samples joined by a line, with the area to the zero line (or to the floor in decibels) filled: what a signal looks
    /// like between the envelope, where a column holds many samples, and the stems, where each sample can be seen alone.
    private func drawSampleLine(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ signal: PlotSignal, _ colour: Color) {
        let plot = t.rect, range = t.viewport.x.range
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
            ctx.fill(area, with: .linearGradient(Gradient(colors: [colour.opacity(0.5 * fill), colour.opacity(0.03 * fill)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        } else {
            let zero = min(1, max(0, (t.y(0) - plot.minY) / plot.height))
            ctx.fill(area, with: .linearGradient(
                Gradient(stops: [.init(color: colour.opacity(0.5 * fill), location: 0), .init(color: colour.opacity(0.08 * fill), location: zero),
                                 .init(color: colour.opacity(0.5 * fill), location: 1)]),
                startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        }
        ctx.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    /// One sample per stem with a head, as an audio editor shows them when it is zoomed in.
    private func drawStems(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ signal: PlotSignal, _ colour: Color, _ pixelsPerSample: CGFloat) {
        let plot = t.rect, range = t.viewport.x.range
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
        ctx.stroke(stems, with: .color(colour.opacity(0.75)), lineWidth: 1.3)
        ctx.fill(heads, with: .color(colour))
        ctx.stroke(heads, with: .color(palette.isDark ? Color.white.opacity(0.55) : Color.white.opacity(0.9)), lineWidth: 0.8)
    }

    /// The envelope of the columns: the band between the smallest and the largest sample of each (or the line of the largest
    /// magnitude in decibels), with a gradient, and a stroke on its edges.
    private func drawEnvelope(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ scale: CGFloat, _ cache: EnvelopeCache, _ signal: PlotSignal, _ colour: Color) {
        let plot = t.rect
        let columns = min(4000, max(2, Int(plot.width * scale)))
        let range = t.viewport.x.range
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
            ctx.fill(area, with: .linearGradient(Gradient(colors: [colour.opacity(0.5 * fill), colour.opacity(0.03 * fill)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
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
            Gradient(stops: [.init(color: colour.opacity(0.55 * fill), location: 0), .init(color: colour.opacity(0.10 * fill), location: zero),
                             .init(color: colour.opacity(0.55 * fill), location: 1)]),
            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        ctx.stroke(top, with: .color(colour), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
        ctx.stroke(bottom, with: .color(colour.opacity(0.8)), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
    }

    // MARK: Reading the data off

    /// The sample under a point of the view, when the samples can be told apart, and the trace whose value there is nearest to
    /// the pointer (the only one, when there is one).
    private func snapped(_ p: CGPoint, _ t: PlotTransform) -> (index: Int, trace: Int)? {
        let span = t.viewport.x.range.upperBound - t.viewport.x.range.lowerBound
        let i = Int(t.xValue(p.x).rounded())
        guard span > 0, t.rect.width / CGFloat(span) >= Self.lineThreshold, i >= 0 else { return nil }
        var best: (trace: Int, distance: CGFloat)?
        for (k, trace) in traces.enumerated() where i < trace.signal.count {
            let d = abs(t.y(amplitude.value(trace.signal.sample(at: i))) - p.y)
            if best == nil || d < best!.distance { best = (k, d) }
        }
        return best.map { (i, $0.trace) }
    }

    func probe(at p: CGPoint, _ t: PlotTransform) -> PlotProbe {
        let seconds = { (n: Double) in sampleRate.flatMap { $0 > 0 ? TickLabels.engineering(n / $0, unit: "s") : nil } ?? "n = \(Int(n.rounded()))" }
        func level(_ v: Double) -> String {
            amplitude.isDecibels ? TickLabels.number(v, decimals: 1) + " dB" : TickLabels.number(v, decimals: abs(v) < 0.1 ? 4 : 3)
        }
        if let (i, k) = snapped(p, t) {
            let signal = traces[k].signal
            let v = Double(signal.sample(at: i)), shown = amplitude.value(signal.sample(at: i))
            var card = [String]()
            if traces.count > 1 { card.append(traces[k].name) }
            if let sr = sampleRate, sr > 0 { card.append("t = " + TickLabels.engineering(Double(i) / sr, unit: "s")) }
            card.append("n = \(i)")
            card.append(TickLabels.number(v, decimals: 4) + "  (" + (v == 0 ? "−∞" : TickLabels.number(20 * log10(abs(v)), decimals: 1)) + " dB)")
            return PlotProbe(point: CGPoint(x: t.x(Double(i)), y: t.y(shown)), xFlag: seconds(Double(i)), yFlag: level(shown), card: card, onData: true,
                             trace: k, customColor: traces[k].color)
        }
        return PlotProbe(point: p, xFlag: seconds(t.xValue(p.x)), yFlag: level(t.yValue(p.y)), card: [], onData: false)
    }

    func measurePoint(at p: CGPoint, _ t: PlotTransform) -> (x: Double, y: Double) {
        if let (i, k) = snapped(p, t) { return (Double(i), amplitude.value(traces[k].signal.sample(at: i))) }
        return (t.xValue(p.x), t.yValue(p.y))
    }

    func measureReadout(_ m: PlotSegment) -> [String] {
        let dx = m.x1 - m.x0, dy = m.y1 - m.y0
        var lines: [String] = []
        if let sr = sampleRate, sr > 0 {
            lines.append("Δt = " + TickLabels.engineering(dx / sr, unit: "s") + "  (\(Int(dx.rounded())) n)")
            if dx != 0 { lines.append("1/Δt = " + TickLabels.engineering(abs(sr / dx), unit: "Hz")) }
        } else {
            lines.append("Δn = \(Int(dx.rounded()))")
        }
        lines.append("Δ = " + (amplitude.isDecibels ? TickLabels.number(dy, decimals: 1) + " dB" : TickLabels.number(dy, decimals: 4)))
        return lines
    }

    func autoscale(_ v: PlotViewport) -> PlotViewport {
        // The extremes of all the traces over the horizontal range.
        var lo = Float.infinity, hi = -Float.infinity, any = false
        for trace in traces {
            var e = Envelope()
            trace.signal.envelope(from: v.x.range.lowerBound, to: v.x.range.upperBound, columns: 1, into: &e)
            guard !e.valid.isEmpty else { continue }
            lo = min(lo, e.lo[0]); hi = max(hi, e.hi[0]); any = true
        }
        guard any else { return v }
        switch amplitude {
        case .linear:
            return v.autoscaledY(extremes: (Double(lo), Double(hi)))
        case .decibels(let floor):
            let top = amplitude.value(max(abs(lo), abs(hi)))
            return v.autoscaledY(extremes: (max(floor, top - 90), top), margin: 0.04)
        }
    }
}
