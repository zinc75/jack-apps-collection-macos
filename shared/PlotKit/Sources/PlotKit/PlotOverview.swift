// SPDX-License-Identifier: MIT

import SwiftUI

/// What a drag in the minimap does to the window it shows, and the new window it gives.
enum PlotOverviewMath {
    /// How near the pointer must be to an edge of the window to take it, in points.
    static let tolerance: CGFloat = 7

    enum Drag: Equatable {
        /// The start moves; the end stays at this value.
        case start(fixedEnd: Double)
        /// The end moves; the start stays at this value.
        case end(fixedStart: Double)
        /// The window slides; the pointer holds it at this distance from its start (in the units of the axis).
        case slide(grab: Double)
    }

    /// What a press does, given where the window is on the screen (`lo` and `hi`) and in the data.
    static func begin(at x: CGFloat, lo: CGFloat, hi: CGFloat, window: ClosedRange<Double>, valueAtPointer: Double) -> Drag {
        let nearLo = abs(x - lo) <= tolerance, nearHi = abs(x - hi) <= tolerance
        if nearLo || nearHi {
            if nearLo && nearHi { return x < (lo + hi) / 2 ? .start(fixedEnd: window.upperBound) : .end(fixedStart: window.lowerBound) }
            return nearLo ? .start(fixedEnd: window.upperBound) : .end(fixedStart: window.lowerBound)
        }
        if x > lo, x < hi { return .slide(grab: valueAtPointer - window.lowerBound) }
        // A press outside the window puts the window there, centred on the pointer.
        return .slide(grab: (window.upperBound - window.lowerBound) / 2)
    }

    /// The window to show after the pointer moved to `value`.
    static func window(for drag: Drag, original: ClosedRange<Double>, value: Double, minSpan: Double) -> ClosedRange<Double> {
        switch drag {
        case .start(let end):
            return min(value, end - minSpan)...end
        case .end(let start):
            return start...max(value, start + minSpan)
        case .slide(let grab):
            let span = original.upperBound - original.lowerBound
            let low = value - grab
            return low...(low + span)
        }
    }
}

/// How the window of the minimap looks.
public enum PlotOverviewStyle: Sendable {
    /// A thick rounded frame with solid ends carrying two thin bars, as the trim bar of QuickTime Player, in a rounded container.
    case trim
    /// A thin frame with two capsules of glass at its edges.
    case glass
}

/// A small picture of a whole signal with the part the plot shows as a window over it: drag the window to slide the plot, its edges to
/// zoom, or press outside it to bring the plot there. It follows the horizontal axis of the viewport it is given, and the region of the
/// plot if there is one.
public struct PlotOverview: View {
    let signal: PlotSignal
    @Binding var viewport: PlotViewport
    var region: ClosedRange<Double>?
    var regionColor: Color
    var accent: Color
    var windowColor: Color?
    var height: CGFloat
    var style: PlotOverviewStyle

    @Environment(\.colorScheme) private var colorScheme
    @State private var drag: PlotOverviewMath.Drag?
    @State private var original: ClosedRange<Double>?

    /// The gold of the frame of the window, a little softer than the yellow of the trim bar of QuickTime Player: a colour of its own, not the accent,
    /// which the region has, and not the blue of the box of a zoom.
    public static let trimGold = Color(red: 1.0, green: 0.78, blue: 0.22)

    private var windowTint: Color { windowColor ?? Self.trimGold }

    /// - Parameters:
    ///   - windowColor: the colour of the frame of the window (`trimGold` by default).
    public init(signal: PlotSignal, viewport: Binding<PlotViewport>, region: ClosedRange<Double>? = nil, regionColor: Color = .accentColor,
                accent: Color = .accentColor, windowColor: Color? = nil, height: CGFloat = 72, style: PlotOverviewStyle = .trim) {
        self.signal = signal
        _viewport = viewport
        self.region = region
        self.regionColor = regionColor
        self.accent = accent
        self.windowColor = windowColor
        self.height = height
        self.style = style
    }

    private var bounds: ClosedRange<Double> { viewport.x.bounds }

    /// The space between the container and the strip it holds: the same on the four sides, so that the corners can be concentric.
    private static let trimInset: CGFloat = 6
    private var insetX: CGFloat { style == .trim ? Self.trimInset : 0 }
    private var insetY: CGFloat { style == .trim ? Self.trimInset : 0 }
    /// Concentric corners: the radius of what is inside is the radius of what holds it less the space between them (14 − 6 = 8), for the strip,
    /// for the frame of the window and for the ends of the frame. The inside of the thick frame is concentric too (8 − its thickness).
    private static let containerRadius: CGFloat = 14
    private static let windowRadius: CGFloat = containerRadius - trimInset
    private static let trimCapWidth: CGFloat = 9
    /// The width that takes the pointer over an edge of the window with the glass style (wider than what is drawn).
    private static let gripHitWidth: CGFloat = 18

    public var body: some View {
        GeometryReader { geometry in
            let strip = max(geometry.size.width - 2 * insetX, 1)
            let window = viewport.x.range
            let lo = insetX + pixel(window.lowerBound, strip), hi = insetX + pixel(window.upperBound, strip)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(&context, size) }
                // What the pointer shows over the window and over its edges: it can be moved, and the edges stretched.
                Color.clear
                    .frame(width: max(hi - lo, 0), height: height)
                    .offset(x: lo)
                    .contentShape(Rectangle())
                    .pointerStyle(drag == nil ? .grabIdle : .grabActive)
                grip(left: true, width: hi - lo).offset(x: gripX(left: true, lo: lo, hi: hi), y: insetY)
                grip(left: false, width: hi - lo).offset(x: gripX(left: false, lo: lo, hi: hi), y: insetY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in changed(gesture, width: strip) }
                .onEnded { _ in drag = nil; original = nil })
        }
        .frame(height: height)
        .accessibilityLabel("Overview")
    }

    private func pixel(_ value: Double, _ width: CGFloat) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        return span > 0 ? CGFloat((value - bounds.lowerBound) / span) * width : 0
    }

    private func value(_ x: CGFloat, _ width: CGFloat) -> Double {
        let span = bounds.upperBound - bounds.lowerBound
        return width > 0 ? bounds.lowerBound + Double(min(max(x / width, 0), 1)) * span : bounds.lowerBound
    }

    private func changed(_ gesture: DragGesture.Value, width: CGFloat) {
        let window = original ?? viewport.x.range
        if drag == nil {
            original = window
            let start = gesture.startLocation.x - insetX
            drag = PlotOverviewMath.begin(at: start, lo: pixel(window.lowerBound, width), hi: pixel(window.upperBound, width),
                                          window: window, valueAtPointer: value(start, width))
        }
        guard let drag else { return }
        let wanted = PlotOverviewMath.window(for: drag, original: window, value: value(gesture.location.x - insetX, width), minSpan: max(viewport.x.minSpan, 1e-9))
        viewport.x = viewport.x.showing(wanted)
    }

    // MARK: Handles

    /// Where a handle is: centred on its edge for glass; for the trim bar, inside the frame (the ends are part of it).
    private func gripX(left: Bool, lo: CGFloat, hi: CGFloat) -> CGFloat {
        switch style {
        case .glass: return (left ? lo : hi) - Self.gripHitWidth / 2
        case .trim:
            let width = min(Self.trimCapWidth, max((hi - lo) / 2, 6))
            return left ? lo : hi - width
        }
    }

    /// A handle of the window, with the pointer of a stretch.
    @ViewBuilder private func grip(left: Bool, width window: CGFloat) -> some View {
        switch style {
        case .glass:
            Group {
                if #available(macOS 26.0, *) {
                    Color.clear.frame(width: 10, height: height - 14).glassEffect(.regular, in: .capsule)
                } else {
                    Capsule().fill(.regularMaterial).frame(width: 10, height: height - 14)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
            }
            .frame(width: Self.gripHitWidth, height: height)
            .offset(y: -insetY)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
        case .trim:
            let r = Self.windowRadius
            let corners = left
                ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0)
                : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r)
            ZStack {
                corners.fill(windowTint)
                // Two thin bars, as the ends of the trim bar of QuickTime have.
                HStack(spacing: 2) {
                    Capsule().fill(Color.black.opacity(0.45)).frame(width: 1.25, height: 16)
                    Capsule().fill(Color.black.opacity(0.45)).frame(width: 1.25, height: 16)
                }
            }
            .frame(width: min(Self.trimCapWidth, max(window / 2, 6)), height: height - 2 * insetY)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let palette = PlotPalette(accent: accent, isDark: colorScheme == .dark)
        let frame = CGRect(origin: .zero, size: size)
        let strip = CGRect(x: insetX, y: insetY, width: max(size.width - 2 * insetX, 1), height: max(size.height - 2 * insetY, 1))
        switch style {
        case .trim:
            // The container: dark, very rounded, with a hairline.
            let container = Path(roundedRect: frame, cornerRadius: Self.containerRadius)
            context.fill(container, with: .color(palette.isDark ? Color.black.opacity(0.36) : Color.black.opacity(0.07)))
            context.stroke(container, with: .color(palette.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)), lineWidth: 0.75)
        case .glass:
            context.fill(Path(roundedRect: frame, cornerRadius: 4), with: .color(palette.background))
        }

        // The signal, the region and the dimming are in the strip, which has the corners of the frame of the window.
        var inner = context
        if style == .trim { inner.clip(to: Path(roundedRect: strip, cornerRadius: Self.windowRadius)) }

        // The signal, in the strip.
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

        // The region of the plot, as a band along the bottom of the strip.
        if let region {
            let a = strip.minX + pixel(region.lowerBound, strip.width), b = strip.minX + pixel(region.upperBound, strip.width)
            inner.fill(Path(roundedRect: CGRect(x: a, y: strip.maxY - 7, width: max(b - a, 1), height: 3), cornerRadius: 1.5), with: .color(regionColor))
        }

        // The window: what is outside it is dimmed.
        let window = viewport.x.range
        let lo = strip.minX + pixel(window.lowerBound, strip.width), hi = strip.minX + pixel(window.upperBound, strip.width)
        let dim = palette.isDark ? Color.black.opacity(0.50) : Color.black.opacity(0.18)
        // Plain rectangles: the corners of the strip come from the clip.
        var outside = Path()
        if lo > strip.minX { outside.addRect(CGRect(x: strip.minX, y: strip.minY, width: lo - strip.minX, height: strip.height)) }
        if hi < strip.maxX { outside.addRect(CGRect(x: hi, y: strip.minY, width: strip.maxX - hi, height: strip.height)) }
        inner.fill(outside, with: .color(dim))
        switch style {
        case .glass:
            let box = CGRect(x: lo, y: 0.75, width: max(hi - lo, 2), height: size.height - 1.5)
            context.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(palette.text), lineWidth: 1.5)
        case .trim:
            // The thick rounded frame: the ends are the handles, drawn over it.
            let line: CGFloat = 2.5
            let box = CGRect(x: lo, y: strip.minY, width: max(hi - lo, 2), height: strip.height)
            context.stroke(Path(roundedRect: box.insetBy(dx: line / 2, dy: line / 2), cornerRadius: Self.windowRadius - line / 2), with: .color(windowTint), lineWidth: line)
        }
    }
}
