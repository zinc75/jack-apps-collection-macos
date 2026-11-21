// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import SwiftUI

/// The curve of an impulse response: the samples themselves, joined by a line when the view is zoomed in (with a dot on each sample when it
/// is zoomed in a lot), and for each column of pixels the lowest and the highest sample when it is zoomed out, so that no peak is lost.
/// Drag to move, pinch or use the buttons to zoom, double-click to see everything.
struct ImpulseCurveView: View {
    @Environment(\.appAccentColor) private var accent
    let data: CurveData
    /// The part the engine reads, and the marks of the analysis, in frames (nil when unknown).
    var used: Range<Int>?
    var attack: Int?
    var tail: Int?

    @State private var start = 0.0
    @State private var span = 0.0
    @State private var dragOrigin: Double?
    @State private var zoomOrigin: Double?
    @State private var decibels = false

    private let leftMargin: CGFloat = 44, bottomMargin: CGFloat = 20

    private var total: Double { Double(max(data.count, 1)) }
    private var visibleSpan: Double { span > 0 ? min(span, total) : total }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                Canvas { context, size in draw(&context, size) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        let plotWidth = max(geometry.size.width - leftMargin, 1)
                        let origin = dragOrigin ?? start
                        dragOrigin = origin
                        start = clamp(origin - Double(value.translation.width) / Double(plotWidth) * visibleSpan, span: visibleSpan)
                    }.onEnded { _ in dragOrigin = nil })
                    .gesture(MagnifyGesture().onChanged { value in
                        let origin = zoomOrigin ?? visibleSpan
                        zoomOrigin = origin
                        zoom(to: origin / Double(value.magnification), around: 0.5)
                    }.onEnded { _ in zoomOrigin = nil })
                    .onTapGesture(count: 2) { start = 0; span = 0 }
                    .accessibilityLabel("Courbe de la réponse impulsionnelle")
            }
            .frame(height: 190)
            .blockBackground()
            HStack(spacing: 8) {
                Button { zoom(to: visibleSpan / 2, around: 0.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("Agrandir")
                Button { zoom(to: visibleSpan * 2, around: 0.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("Réduire")
                Button("Tout voir") { start = 0; span = 0 }
                Picker("Échelle", selection: $decibels) {
                    Text("Linéaire").tag(false)
                    Text("dB").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
                Spacer()
                Text(verbatim: "\(Int(visibleSpan)) / \(data.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func clamp(_ s: Double, span: Double) -> Double { min(max(s, 0), max(total - span, 0)) }

    private func zoom(to newSpan: Double, around fraction: Double) {
        let new = min(max(newSpan, 8), total)
        let center = start + visibleSpan * fraction
        span = new
        start = clamp(center - new * fraction, span: new)
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let plot = CGRect(x: leftMargin, y: 4, width: max(size.width - leftMargin - 6, 1), height: max(size.height - bottomMargin - 8, 1))
        let peak = max(data.peak, 1e-9)
        let scale: CurveScale = decibels ? .decibels(floorDB: -90) : .linear
        let mid = plot.midY, half = plot.height / 2 * 0.96
        func y(_ v: Float) -> CGFloat { mid - CGFloat(scale.height(of: v, reference: peak)) * half }
        let end = start + visibleSpan
        let perPixel = visibleSpan / Double(plot.width)
        func x(_ frame: Double) -> CGFloat { plot.minX + CGFloat((frame - start) / visibleSpan) * plot.width }

        // The part the engine does not read is dimmed.
        if let used {
            let a = x(Double(used.lowerBound)), b = x(Double(used.upperBound))
            let dim = Color.black.opacity(0.35)
            if a > plot.minX { context.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: min(a, plot.maxX) - plot.minX, height: plot.height)), with: .color(dim)) }
            if b < plot.maxX { context.fill(Path(CGRect(x: max(b, plot.minX), y: plot.minY, width: plot.maxX - max(b, plot.minX), height: plot.height)), with: .color(dim)) }
        }

        // The axes: the zero line, the amplitude marks, and the time marks in milliseconds.
        let grid = Color.secondary.opacity(0.35)
        var zero = Path(); zero.move(to: CGPoint(x: plot.minX, y: mid)); zero.addLine(to: CGPoint(x: plot.maxX, y: mid))
        context.stroke(zero, with: .color(grid), lineWidth: 1)
        let marks: [(Float, String)] = decibels
            ? [(peak, "0 dB"), (peak * 0.0316, "−30"), (peak * 0.001, "−60")]
            : [(peak, "1"), (peak / 2, "0,5")]
        for (value, label) in marks {
            for sign: Float in [1, -1] {
                let yy = y(sign * value)
                var line = Path(); line.move(to: CGPoint(x: plot.minX, y: yy)); line.addLine(to: CGPoint(x: plot.maxX, y: yy))
                context.stroke(line, with: .color(grid.opacity(0.5)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                if sign > 0 { context.draw(Text(verbatim: label).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: plot.minX - 4, y: yy), anchor: .trailing) }
            }
        }
        let rate = data.sampleRate
        let msPerPixel = perPixel / rate * 1000
        let steps: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000]
        let step = steps.first { $0 / msPerPixel >= 70 } ?? 2000
        var t = (start / rate * 1000 / step).rounded(.up) * step
        while t / 1000 * rate <= end {
            let xx = x(t / 1000 * rate)
            var tick = Path(); tick.move(to: CGPoint(x: xx, y: plot.maxY)); tick.addLine(to: CGPoint(x: xx, y: plot.maxY + 4))
            context.stroke(tick, with: .color(grid), lineWidth: 1)
            let text = step < 1 ? t.formatted(.number.precision(.fractionLength(2))) : t.formatted(.number.precision(.fractionLength(0...1)))
            context.draw(Text(verbatim: text + " ms").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: xx, y: plot.maxY + 12), anchor: .center)
            t += step
        }

        // The curve.
        var curve = Path()
        let first = max(Int(start.rounded(.down)), 0), last = min(Int(end.rounded(.up)), data.count - 1)
        let pixelsPerSample = 1 / perPixel
        if pixelsPerSample >= 2, first <= last {
            for i in first...last {
                let p = CGPoint(x: x(Double(i)), y: y(data.samples[i]))
                i == first ? curve.move(to: p) : curve.addLine(to: p)
            }
            context.clip(to: Path(plot))
            context.stroke(curve, with: .color(accent), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            if pixelsPerSample >= 7 {
                for i in first...last {
                    let p = CGPoint(x: x(Double(i)), y: y(data.samples[i]))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(accent))
                }
            }
        } else {
            let columns = data.columns(from: start, to: end, width: max(Int(plot.width), 1))
            for c in 0..<columns.minimums.count {
                let xx = plot.minX + CGFloat(c) + 0.5
                curve.move(to: CGPoint(x: xx, y: y(columns.maximums[c])))
                let low = y(columns.minimums[c]), high = y(columns.maximums[c])
                curve.addLine(to: CGPoint(x: xx, y: low == high ? low + 0.5 : low))
            }
            context.clip(to: Path(plot))
            context.stroke(curve, with: .color(accent), lineWidth: 1)
        }

        // The marks of the analysis.
        for (frame, color) in [(attack, Color.green), (tail, Color.orange)] {
            guard let frame, Double(frame) >= start, Double(frame) <= end else { continue }
            var mark = Path(); mark.move(to: CGPoint(x: x(Double(frame)), y: plot.minY)); mark.addLine(to: CGPoint(x: x(Double(frame)), y: plot.maxY))
            context.stroke(mark, with: .color(color), lineWidth: 1.5)
        }
    }
}
