// SPDX-License-Identifier: MIT

import SwiftUI

/// A curve of points whose abscissas are anything that increases: the magnitude of a spectrum at its frequencies, a phase, a group
/// delay. There is no pyramid and no regular step: the points are drawn as they are, or reduced to the extremes of each column of
/// pixels when there are many more than the pixels.
public struct PlotCurve: Identifiable {
    public let id = UUID()
    public var name: String
    /// Increasing.
    public var x: [Double]
    public var y: [Double]
    /// `nil`: a colour of the palette.
    public var color: Color?
    /// Whether the area under the curve has a gradient.
    public var filled: Bool
    /// The unit, if the values are a phase: it can then be unwrapped, and its delay removed (the inspector offers both).
    public var phase: PhaseUnit?
    /// The delay to remove from a phase, in seconds (the abscissas being hertz): the time of the direct sound of an impulse
    /// response, say. Without it the delay is the one of the straight line that fits the unwrapped phase.
    public var delay: Double?
    /// The values are linear magnitudes: the inspector offers to smooth them in fractions of an octave.
    public var isMagnitude: Bool
    /// A curve drawn thin and pale behind the others, which cannot be read off: the raw spectrum behind its smoothed one.
    public var isReference = false
    /// The values are a group delay (in milliseconds): they can be smoothed in fractions of an octave too, as plain means.
    public var isGroupDelay = false

    public init(name: String, x: [Double], y: [Double], color: Color? = nil, filled: Bool = true, phase: PhaseUnit? = nil, delay: Double? = nil,
                isMagnitude: Bool = false) {
        self.isMagnitude = isMagnitude
        self.name = name
        self.x = x
        self.y = y
        self.color = color
        self.filled = filled
        self.phase = phase
        self.delay = delay
    }

    /// The group delay of a phase, in milliseconds: minus the slope of the unwrapped phase, `−dφ/dω`. The slope at a point is taken
    /// between its two neighbours (one-sided at the ends), whatever the spacing of the abscissas, which are hertz. A curve that is
    /// not a phase is returned as it is.
    public func groupDelay() -> PlotCurve {
        guard let phase else { return self }
        let u = unwrapped()
        let n = min(u.x.count, u.y.count)
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n where u.y[i].isFinite && u.x[i].isFinite {
            // The nearest finite neighbours on each side.
            var a = i - 1, b = i + 1
            while a >= 0, !(u.y[a].isFinite && u.x[a].isFinite) { a -= 1 }
            while b < n, !(u.y[b].isFinite && u.x[b].isFinite) { b += 1 }
            let lo = a >= 0 ? a : i, hi = b < n ? b : i
            guard hi != lo, u.x[hi] != u.x[lo] else { continue }
            let slope = (u.y[hi] - u.y[lo]) / (u.x[hi] - u.x[lo])   // phase units per hertz
            out[i] = -slope / phase.period * 1000
        }
        var copy = self
        copy.y = out
        copy.phase = nil
        copy.delay = nil
        copy.isGroupDelay = true
        return copy
    }

    /// The delay, in seconds, of the straight line that fits the unwrapped phase best (least squares): the mean delay, which for an
    /// impulse response is its centre of energy in time. nil when there are too few points or the abscissas do not vary.
    public func estimatedDelay() -> Double? {
        guard let phase else { return nil }
        let u = unwrapped()
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for i in 0..<min(u.y.count, u.x.count) where u.y[i].isFinite && u.x[i].isFinite {
            n += 1; sx += u.x[i]; sy += u.y[i]; sxx += u.x[i] * u.x[i]; sxy += u.x[i] * u.y[i]
        }
        let denominator = n * sxx - sx * sx
        guard n >= 2, abs(denominator) > 1e-12 else { return nil }
        let slope = (n * sxy - sx * sy) / denominator   // phase units per hertz
        return -slope / phase.period
    }

    /// The curve as it is drawn: the phase unwrapped, and/or without its delay. Taking the delay away adds the straight line that
    /// the delay makes, `period × f × delay`; unwrapped the result stays continuous, otherwise it is brought back between
    /// −half a period and +half a period. A curve that is not a phase is returned as it is.
    public func processed(unwrap: Bool, removeDelay: Bool) -> PlotCurve {
        guard let phase, unwrap || removeDelay else { return self }
        var copy = unwrap ? unwrapped() : self
        if removeDelay, let seconds = delay ?? estimatedDelay() {
            let period = phase.period
            for i in 0..<min(copy.y.count, copy.x.count) where copy.y[i].isFinite && copy.x[i].isFinite {
                var v = copy.y[i] + period * copy.x[i] * seconds
                if !unwrap { v -= period * ((v + period / 2) / period).rounded(.down) }
                copy.y[i] = v
            }
        }
        return copy
    }

    /// The same curve with its phase unwrapped: each value is brought within half a period of the one before it, by adding whole
    /// periods, so that the jumps from +180° to −180° become a continuous line. A value that is not finite is skipped, and the
    /// unwrapping goes on after it. A curve that is not a phase is returned as it is.
    public func unwrapped() -> PlotCurve {
        guard let phase else { return self }
        let period = phase.period
        var out = y
        var offset = 0.0
        var previous: Double?
        for i in 0..<min(y.count, x.count) where y[i].isFinite {
            if let p = previous { offset -= period * ((y[i] - p) / period).rounded() }
            out[i] = y[i] + offset
            previous = y[i]
        }
        var copy = self
        copy.y = out
        return copy
    }

    var count: Int { min(x.count, y.count) }

    /// The index of the first abscissa that is not below `v` (the count when there is none).
    func lowerBound(_ v: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if x[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The index of the abscissa nearest to `v`.
    func nearest(_ v: Double) -> Int? {
        guard count > 0 else { return nil }
        let i = lowerBound(v)
        if i == 0 { return 0 }
        if i >= count { return count - 1 }
        return abs(x[i] - v) < abs(x[i - 1] - v) ? i : i - 1
    }
}

/// The unit of a phase.
public enum PhaseUnit: Sendable, Equatable {
    case degrees, radians

    /// One turn, in this unit.
    public var period: Double { self == .degrees ? 360 : 2 * .pi }
}

extension PlotViewport {
    /// The view that shows all of some curves: their abscissas on the horizontal axis (from the smallest positive one when it is
    /// logarithmic, which has no zero), their values as the scale draws them on the vertical one, with a margin.
    ///
    /// - Parameter visibleX: the part of the abscissas to show at first (20 to 20 000 Hz for a spectrum whose first bin is at a
    ///   fraction of a hertz); the bounds stay those of all the data, so that one can still zoom out to see them.
    public static func curves(_ curves: [PlotCurve], xScale: AxisScale = .linear, yScale: AmplitudeScale = .linear,
                              visibleX: ClosedRange<Double>? = nil) -> PlotViewport {
        let xs = curves.flatMap { $0.x.prefix($0.count) }.filter { $0.isFinite }
        let positive = xs.filter { $0 > 0 }
        var xLow = (xScale == .logarithmic ? positive.min() : xs.min()) ?? 0
        var xHigh = xs.max() ?? 1
        if xHigh <= xLow { xHigh = xLow + 1 }
        if xScale == .logarithmic, xLow <= 0 { xLow = 1e-3 }
        let ys = curves.flatMap { c in c.y.prefix(c.count).filter { $0.isFinite }.map { yScale.value($0) } }
        var yLow = ys.min() ?? -1, yHigh = ys.max() ?? 1
        if yHigh - yLow < 1e-12 { yLow -= 0.5; yHigh += 0.5 }
        let pad = (yHigh - yLow) * 0.06
        yLow -= pad; yHigh += pad
        if case .decibels(let floor) = yScale { yLow = max(floor - 1, yLow) }
        var x = AxisState(bounds: xLow...xHigh, scale: xScale, minSpan: xScale == .logarithmic ? 1.01 : (xHigh - xLow) * 1e-4)
        x = x.fitted()
        if let visibleX { x = x.showing(visibleX) }
        let y = AxisState(bounds: yLow...yHigh, minSpan: yScale.isDecibels ? 0.5 : (yHigh - yLow) * 1e-6)
        return PlotViewport(x: x, y: y)
    }
}

/// The content of a plot of curves.
struct CurveContent: PlotContent {
    var curves: [PlotCurve]
    var yScale: AmplitudeScale
    var xUnitText: String
    var yUnitText: String
    var gradient = PlotGradient()

    /// The area under a line (to the baseline) is a gradient or nothing; the band of the extremes, which is the body of a dense
    /// curve, is always there.
    private var gradientStrength: Double {
        if case .gradient(let k) = gradient.fill(curves: curves.filter { !$0.isReference }.count) { return k }
        return 0
    }

    var xUnit: String { xUnitText }
    var xDivisor: Double { 1 }
    var xIntegers: Bool { false }
    var xCaption: String { "" }
    var yUnit: String { yScale.isDecibels ? "dB" : yUnitText }
    var hasZeroLine: Bool { true }
    var measureKey: AnyHashable { yScale }

    private func colour(_ i: Int, _ palette: PlotPalette) -> Color { palette.trace(i, curves[i].color) }

    private func level(_ v: Double) -> Double { yScale.value(v) }

    // MARK: Drawing

    func drawData(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette, _ scale: CGFloat, _ cache: EnvelopeCache) {
        // The first curve is drawn last, over the others.
        for i in curves.indices.reversed() { draw(curves[i], colour(i, palette), &ctx, t, palette) }
    }

    private func draw(_ curve: PlotCurve, _ baseColour: Color, _ ctx: inout GraphicsContext, _ t: PlotTransform, _ palette: PlotPalette) {
        // A reference (the raw spectrum behind its smoothed one) is thin and pale, and has no fill.
        let thin = curve.isReference
        let colour = thin ? baseColour.opacity(0.42) : baseColour
        let plot = t.rect, range = t.viewport.x.range
        let n = curve.count
        guard n > 1 else { return }
        let first = max(0, curve.lowerBound(range.lowerBound) - 1), last = min(n - 1, curve.lowerBound(range.upperBound))
        guard last > first else { return }
        let count = last - first + 1
        let baseline = (yScale.isDecibels || !t.viewport.y.range.contains(0)) ? plot.maxY + 2 : t.y(0)
        let gradient = Gradient(colors: [colour.opacity(0.40 * gradientStrength), colour.opacity(0.03 * gradientStrength)])
        let filled = curve.filled && gradientStrength > 0 && !thin
        let start = CGPoint(x: 0, y: plot.minY), end = CGPoint(x: 0, y: plot.maxY)

        if count <= 3 * Int(plot.width) {
            // Few enough points to draw each: a line, and a dot on each when they are far apart.
            var line = Path(), area = Path()
            var run: (start: CGPoint, end: CGPoint)?
            var dots = Path()
            let spacing = plot.width / CGFloat(max(1, count))
            for i in first...last {
                guard curve.y[i].isFinite, curve.x[i].isFinite else {
                    if let r = run { closeArea(&area, r, baseline); run = nil }
                    continue
                }
                let p = CGPoint(x: t.x(curve.x[i]), y: t.y(level(curve.y[i])))
                if let r = run { line.addLine(to: p); area.addLine(to: p); run = (r.start, p) }
                else { line.move(to: p); area.move(to: p); run = (p, p) }
                if spacing > 14 { dots.addEllipse(in: CGRect(x: p.x - 2.8, y: p.y - 2.8, width: 5.6, height: 5.6)) }
            }
            if let r = run { closeArea(&area, r, baseline) }
            if filled { ctx.fill(area, with: .linearGradient(gradient, startPoint: start, endPoint: end)) }
            ctx.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: thin ? 0.9 : 1.6, lineCap: .round, lineJoin: .round))
            if spacing > 14, !thin {
                ctx.fill(dots, with: .color(colour))
                ctx.stroke(dots, with: .color(palette.isDark ? Color.white.opacity(0.5) : Color.white.opacity(0.9)), lineWidth: 0.8)
            }
            return
        }

        // Many more points than pixels: one line through the mean of each column of one point, and the range between its smallest
        // and its largest value as a light band (two lines for the two edges would read as two curves).
        let columns = max(2, Int(plot.width))
        var lo = [Double](repeating: .infinity, count: columns), hi = [Double](repeating: -.infinity, count: columns)
        var sum = [Double](repeating: 0, count: columns), number = [Int](repeating: 0, count: columns)
        for i in first...last where curve.y[i].isFinite && curve.x[i].isFinite {
            let px = t.x(curve.x[i]) - plot.minX
            guard px >= 0, px < CGFloat(columns) else { continue }
            let c = Int(px), v = level(curve.y[i])
            if v < lo[c] { lo[c] = v }
            if v > hi[c] { hi[c] = v }
            sum[c] += v; number[c] += 1
        }
        var line = Path(), band = Path()
        var started = false
        var firstX = plot.minX, lastX = plot.minX
        var lows: [CGPoint] = []
        for c in 0..<columns where number[c] > 0 {
            let x = plot.minX + CGFloat(c) + 0.5
            let mean = CGPoint(x: x, y: t.y(sum[c] / Double(number[c])))
            if started { line.addLine(to: mean); band.addLine(to: CGPoint(x: x, y: t.y(hi[c]))) }
            else { line.move(to: mean); band.move(to: CGPoint(x: x, y: t.y(hi[c]))); started = true; firstX = x }
            lows.append(CGPoint(x: x, y: t.y(lo[c])))
            lastX = x
        }
        guard started else { return }
        for p in lows.reversed() { band.addLine(to: p) }
        band.closeSubpath()
        ctx.fill(band, with: .color(colour.opacity(thin ? 0.5 : 0.22)))
        // The area under the line, to the baseline.
        if filled {
            var area = line
            area.addLine(to: CGPoint(x: lastX, y: baseline))
            area.addLine(to: CGPoint(x: firstX, y: baseline))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(gradient, startPoint: start, endPoint: end))
        }
        ctx.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: thin ? 0.8 : 1.5, lineJoin: .round))
    }

    private func closeArea(_ area: inout Path, _ run: (start: CGPoint, end: CGPoint), _ baseline: CGFloat) {
        area.addLine(to: CGPoint(x: run.end.x, y: baseline))
        area.addLine(to: CGPoint(x: run.start.x, y: baseline))
        area.closeSubpath()
    }

    // MARK: Reading the data off

    /// The point of a curve nearest the pointer (by its place on the screen), when one is close enough to snap to.
    private func nearestPoint(_ p: CGPoint, _ t: PlotTransform) -> (curve: Int, index: Int, point: CGPoint)? {
        let xv = t.xValue(p.x)
        var best: (curve: Int, index: Int, point: CGPoint, distance: CGFloat)?
        for (k, curve) in curves.enumerated() where !curve.isReference {
            guard let i = curve.nearest(xv), curve.y[i].isFinite else { continue }
            let q = CGPoint(x: t.x(curve.x[i]), y: t.y(level(curve.y[i])))
            let d = hypot(q.x - p.x, q.y - p.y)
            if best == nil || d < best!.distance { best = (k, i, q, d) }
        }
        guard let b = best, abs(b.point.x - p.x) <= 40 else { return nil }
        return (b.curve, b.index, b.point)
    }

    private func xText(_ v: Double) -> String {
        xUnitText.isEmpty ? TickLabels.number(Double(String(format: "%.4g", v)) ?? v, decimals: 2) : TickLabels.engineering(v, unit: xUnitText)
    }

    private func yText(_ v: Double) -> String {
        if yScale.isDecibels { return TickLabels.number(v, decimals: 1) + " dB" }
        // Four significant digits, but not in the scientific notation for a large value (an unwrapped phase runs to hundreds of thousands).
        let t = abs(v) >= 1000 ? String(format: "%.0f", v) : String(format: "%.4g", v)
        return (t.hasPrefix("-") ? "−" + t.dropFirst() : t) + (yUnitText.isEmpty ? "" : " " + yUnitText)
    }

    func probe(at p: CGPoint, _ t: PlotTransform) -> PlotProbe {
        if let n = nearestPoint(p, t) {
            let curve = curves[n.curve]
            let x = curve.x[n.index], y = level(curve.y[n.index])
            var card = [curve.name, xText(x), yText(y)]
            if yScale.isDecibels { card.append("|y| = " + String(format: "%.4g", curve.y[n.index])) }
            return PlotProbe(point: n.point, xFlag: xText(x), yFlag: yText(y), card: card, onData: true, trace: n.curve, customColor: curve.color)
        }
        return PlotProbe(point: p, xFlag: xText(t.xValue(p.x)), yFlag: yText(t.yValue(p.y)), card: [], onData: false)
    }

    func measurePoint(at p: CGPoint, _ t: PlotTransform) -> (x: Double, y: Double) {
        if let n = nearestPoint(p, t) { return (curves[n.curve].x[n.index], level(curves[n.curve].y[n.index])) }
        return (t.xValue(p.x), t.yValue(p.y))
    }

    func measureReadout(_ m: PlotSegment) -> [String] {
        let dx = m.x1 - m.x0, dy = m.y1 - m.y0
        var lines = ["Δ" + (xUnitText.isEmpty ? "x" : "") + " = " + (xUnitText.isEmpty ? String(format: "%.4g", dx) : TickLabels.engineering(dx, unit: xUnitText))]
        if m.x0 > 0, m.x1 > 0, m.x0 != m.x1 {
            let ratio = m.x1 / m.x0
            lines.append(String(format: "×%.4g  (%.3g oct)", ratio, log2(ratio)))
        }
        lines.append("Δ = " + (yScale.isDecibels ? TickLabels.number(dy, decimals: 1) + " dB" : TickLabels.number(dy, decimals: 4) + (yUnitText.isEmpty ? "" : " " + yUnitText)))
        return lines
    }

    func autoscale(_ v: PlotViewport) -> PlotViewport {
        var lo = Double.infinity, hi = -Double.infinity
        for curve in curves where curve.count > 0 {
            let first = max(0, curve.lowerBound(v.x.range.lowerBound) - 1), last = min(curve.count - 1, curve.lowerBound(v.x.range.upperBound))
            guard first <= last else { continue }
            for i in first...last where curve.y[i].isFinite {
                let value = level(curve.y[i])
                lo = min(lo, value); hi = max(hi, value)
            }
        }
        return lo.isFinite ? v.autoscaledY(extremes: (lo, hi)) : v
    }
}
