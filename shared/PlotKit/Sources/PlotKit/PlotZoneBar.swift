// SPDX-License-Identifier: MIT

import SwiftUI

/// A small picture of a whole signal with a range of it that the person can change: the zone a spectrum is computed on, for instance. It looks
/// as the minimap of `PlotOverview` does (a rounded container), but its frame is the range itself: a fine dotted line, as the plot draws the
/// edges of a region, in the colour of the range. Under it is a rail with the same sliders as the ones under the plot of a region (smaller), so the
/// range is edited the same way in both. What it edits is the range, not the part of the signal that a plot shows: drag the sliders to move the
/// start or the end, the part of the rail or of the frame between them to slide the range. While it is dragged, bubbles say where the ends are,
/// in the units of `PlotRegionStyle.format`.
public struct PlotZoneBar: View {
    let signal: PlotSignal
    let editor: PlotRegionEditor
    var accent: Color
    var height: CGFloat

    private enum Gesture { case idle, ignored, dragging(PlotRegionPart, original: ClosedRange<Double>, startValue: Double) }

    @Environment(\.colorScheme) private var colorScheme
    @State private var gesture = Gesture.idle

    private static let inset: CGFloat = 6
    private static let containerRadius: CGFloat = 14
    private static let frameRadius: CGFloat = containerRadius - inset
    private static let hitWidth: CGFloat = 10
    /// The rail of the sliders under the container: lower than the one under a plot, with smaller sliders.
    private static let railHeight: CGFloat = 20
    private static let line: CGFloat = 1.4

    /// - Parameters:
    ///   - editor: the range, how it may change and what the bubbles say; its colour is the one of the frame and the ends.
    ///   - accent: the colour of the signal.
    public init(signal: PlotSignal, zone editor: PlotRegionEditor, accent: Color = .accentColor, height: CGFloat = 64) {
        self.signal = signal
        self.editor = editor
        self.accent = accent
        self.height = height
    }

    private var bounds: ClosedRange<Double> { 0...Double(max(signal.count - 1, 1)) }
    private var range: ClosedRange<Double> { editor.range.wrappedValue }
    private var draggedPart: PlotRegionPart? { if case .dragging(let part, _, _) = gesture { return part } else { return nil } }

    public var body: some View {
        GeometryReader { geometry in
            let strip = max(geometry.size.width - 2 * Self.inset, 1)
            let lo = pixel(range.lowerBound, strip), hi = pixel(range.upperBound, strip)
            let hit = PlotRegionMath.knobHit
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(&context, size) }
                // The part between the ends slides the range, in the frame and on the rail; the ends stretch it.
                let grab: PointerStyle = draggedPart == nil ? .grabIdle : .grabActive
                Color.clear.frame(width: max(hi - lo, 0), height: height).offset(x: lo).contentShape(Rectangle()).pointerStyle(grab)
                Color.clear.frame(width: max(hi - lo - 2 * hit, 0), height: Self.railHeight).offset(x: lo + hit, y: height)
                    .contentShape(Rectangle()).pointerStyle(grab)
                ForEach(Array([lo, hi].enumerated()), id: \.offset) { _, x in
                    Color.clear.frame(width: 2 * PlotRegionMath.tolerance, height: height - 2 * Self.inset).offset(x: x - PlotRegionMath.tolerance, y: Self.inset)
                        .contentShape(Rectangle()).pointerStyle(.columnResize)
                    Color.clear.frame(width: 2 * hit, height: Self.railHeight).offset(x: x - hit, y: height)
                        .contentShape(Rectangle()).pointerStyle(.columnResize)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in changed(value, strip: strip, lo: lo, hi: hi, size: geometry.size) }
                .onEnded { _ in ended() })
        }
        .frame(height: height + Self.railHeight)
        .background(PlotHandleArea())
        .accessibilityLabel("Range")
    }

    private func pixel(_ value: Double, _ width: CGFloat) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        return Self.inset + (span > 0 ? CGFloat((value - bounds.lowerBound) / span) * width : 0)
    }

    private func value(_ x: CGFloat, _ width: CGFloat) -> Double {
        let span = bounds.upperBound - bounds.lowerBound
        return width > 0 ? bounds.lowerBound + Double((x - Self.inset) / width) * span : bounds.lowerBound
    }

    // MARK: The drag

    private func changed(_ value: DragGesture.Value, strip width: CGFloat, lo: CGFloat, hi: CGFloat, size: CGSize) {
        if case .idle = gesture {
            let stripRect = CGRect(x: Self.inset, y: Self.inset, width: width, height: height - 2 * Self.inset)
            let rail = CGRect(x: Self.inset, y: height, width: width, height: Self.railHeight)
            // The sliders and the rail as under a plot; in the frame, the ends, and the part between them slides the range.
            var part = PlotRegionMath.part(at: value.startLocation, lo: lo, hi: hi, plot: stripRect, rail: rail)
            if part == nil, stripRect.contains(value.startLocation), value.startLocation.x > lo, value.startLocation.x < hi { part = .move }
            if let part {
                gesture = .dragging(part, original: range, startValue: self.value(value.startLocation.x, width))
            } else {
                gesture = .ignored
            }
        }
        guard case .dragging(let part, let original, let startValue) = gesture else { return }
        let delta = self.value(value.location.x, width) - startValue
        editor.range.wrappedValue = PlotRegionMath.dragged(part, from: original, by: delta, style: editor.style)
    }

    private func ended() {
        if case .dragging = gesture { editor.onCommit() }
        gesture = .idle
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let isDark = colorScheme == .dark
        let color = editor.style.color(isDark: isDark)
        let frame = CGRect(x: 0, y: 0, width: size.width, height: height)
        let strip = CGRect(x: Self.inset, y: Self.inset, width: max(size.width - 2 * Self.inset, 1), height: max(height - 2 * Self.inset, 1))
        let container = Path(roundedRect: frame, cornerRadius: Self.containerRadius)
        context.fill(container, with: .color(isDark ? Color.black.opacity(0.36) : Color.black.opacity(0.07)))
        context.stroke(container, with: .color(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)), lineWidth: 0.75)

        // The signal and the dimming, in the strip, which has the corners of the frame.
        var inner = context
        inner.clip(to: Path(roundedRect: strip, cornerRadius: Self.frameRadius))
        let columns = max(Int(strip.width), 1)
        var envelope = Envelope(columns: columns)
        signal.envelope(from: bounds.lowerBound, to: bounds.upperBound, columns: columns, into: &envelope)
        var peak: Float = 1e-9
        for c in envelope.valid { peak = max(peak, abs(envelope.lo[c]), abs(envelope.hi[c])) }
        let mid = strip.midY, half = strip.height / 2 * 0.80
        var body = Path()
        for c in envelope.valid {
            let x = strip.minX + CGFloat(c) + 0.5
            let top = mid - CGFloat(envelope.hi[c] / peak) * half, bottom = mid - CGFloat(envelope.lo[c] / peak) * half
            body.move(to: CGPoint(x: x, y: top))
            body.addLine(to: CGPoint(x: x, y: max(bottom, top + 0.6)))
        }
        inner.stroke(body, with: .color(accent.opacity(0.85)), lineWidth: 1)

        let lo = pixel(range.lowerBound, strip.width), hi = pixel(range.upperBound, strip.width)
        var outside = Path()
        if lo > strip.minX { outside.addRect(CGRect(x: strip.minX, y: strip.minY, width: lo - strip.minX, height: strip.height)) }
        if hi < strip.maxX { outside.addRect(CGRect(x: hi, y: strip.minY, width: strip.maxX - hi, height: strip.height)) }
        inner.fill(outside, with: .color(isDark ? Color.black.opacity(0.50) : Color.black.opacity(0.18)))

        // The frame, which is the range.
        let box = CGRect(x: lo, y: strip.minY, width: max(hi - lo, 2), height: strip.height)
        context.stroke(Path(roundedRect: box.insetBy(dx: Self.line / 2, dy: Self.line / 2), cornerRadius: Self.frameRadius - Self.line / 2),
                       with: .color(color), style: StrokeStyle(lineWidth: Self.line, dash: [3, 3]))

        // The rail under the container: its track, the part of it that is the range, and the two sliders.
        let ink = editor.style.onColor(isDark: isDark)
        let rail = CGRect(x: strip.minX, y: height, width: strip.width, height: Self.railHeight)
        let trackY = rail.midY + 1
        context.fill(Path(roundedRect: CGRect(x: rail.minX, y: trackY - 1.5, width: rail.width, height: 3), cornerRadius: 1.5),
                     with: .color(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)))
        let a = min(max(lo, rail.minX), rail.maxX), b = min(max(hi, rail.minX), rail.maxX)
        if b > a {
            context.fill(Path(roundedRect: CGRect(x: a, y: trackY - 2.5, width: b - a, height: 5), cornerRadius: 2.5),
                         with: .color(color.opacity(draggedPart == .move ? 1 : 0.8)))
        }
        let scale = Self.railHeight / PlotRegionMath.railHeight
        for (x, part) in [(lo, PlotRegionPart.start), (hi, PlotRegionPart.end)] {
            PlotRegionKnob.draw(&context, at: x, in: rail, color: color, ink: ink, isActive: draggedPart == part, scale: scale)
        }

        // While it is dragged: where the ends are.
        if draggedPart != nil {
            let startText = editor.style.text(range.lowerBound), endText = editor.style.text(range.upperBound)
            bubble(&context, startText, anchorX: lo, side: .leading, strip: strip, color: color, ink: editor.style.onColor(isDark: isDark))
            bubble(&context, endText, anchorX: hi, side: .trailing, strip: strip, color: color, ink: editor.style.onColor(isDark: isDark))
        }
    }

    /// A bubble beside an end of the frame, on the side where there is room.
    private func bubble(_ context: inout GraphicsContext, _ text: String, anchorX: CGFloat, side: HorizontalEdge, strip: CGRect, color: Color, ink: Color) {
        let resolved = context.resolve(Text(verbatim: text).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundColor(ink))
        let measured = resolved.measure(in: CGSize(width: 240, height: 24))
        let w = measured.width + 12, h = measured.height + 6
        // The start goes to the left of its end if it fits, else inside; the end to the right of its end if it fits, else inside.
        var x: CGFloat
        switch side {
        case .leading: x = anchorX - 4 - w
        case .trailing: x = anchorX + 4
        }
        if x < strip.minX + 2 { x = anchorX + Self.hitWidth + 4 }
        if x + w > strip.maxX - 2 { x = anchorX - Self.hitWidth - 4 - w }
        let rect = CGRect(x: x, y: strip.minY + 5, width: w, height: h)
        context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color))
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }
}
