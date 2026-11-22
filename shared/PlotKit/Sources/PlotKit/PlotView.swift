// SPDX-License-Identifier: MIT

import SwiftUI

/// The plot every kind of data shares: the axes that follow the size of the view, the crosshair, the box zoom, the measure, the
/// gestures and the toolbar. What differs (how the data are drawn and read off) comes from the content.
///
/// - A pinch zooms around the pointer, and so does the wheel of a mouse; a precise scroll (trackpad, Magic Mouse) slides, and
///   zooms with ⌘. Whatever zooms (a pinch, the wheel, ⌘ and a scroll, the zoom buttons) acts on the horizontal axis, with ⌥
///   on the vertical axis, with ⇧ on both.
/// - A drag in the plot area draws a box to zoom to, slides, or measures, as the toolbar says; ⇧ slides whatever the mode is.
/// - A drag on an axis slides it (the middle) or changes its scale (the ends); a double click shows everything, or on the
///   vertical axis fits it to what the horizontal range shows.
struct PlotView: View {
    var content: any PlotContent
    @Binding var viewport: PlotViewport
    var accent: Color
    var labels: PlotLabels
    var controller: PlotController?
    var previewHover: CGPoint?
    var previewMeasure: PlotSegment?
    var previewBox: PlotMeasure?

    @State private var localMode: PlotMode = .zoomBox
    @State private var hover: CGPoint?
    /// The measure between two points of the data: it follows the data when the view moves, and ends with the mode.
    @State private var measure: PlotSegment?
    @State private var drag: Drag?
    @State private var cache = EnvelopeCache()
    @State private var plotSize = CGSize.zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private enum Drag {
        case box(PlotMeasure)
        case pan(last: CGPoint)
        case axis(isX: Bool, part: AxisPart, start: AxisState, from: CGPoint)
        case measure
    }

    private var mode: PlotMode { controller?.mode ?? localMode }
    private var modeBinding: Binding<PlotMode> {
        Binding(get: { controller?.mode ?? localMode }, set: { if let controller { controller.mode = $0 } else { localMode = $0 } })
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller == nil {
                PlotToolbar(mode: modeBinding, labels: labels, accent: accent,
                            zoomIn: { zoomButton(PlotGestures.buttonFactor) }, zoomOut: { zoomButton(1 / PlotGestures.buttonFactor) },
                            autoscale: { viewport = content.autoscale(viewport) }, reset: { viewport = viewport.fitted() })
            }
            GeometryReader { geometry in
                let layout = PlotLayout(size: geometry.size)
                // The commands of the window toolbar act on this plot: they are given again with each state of it.
                let _ = controller?.zoomAction = { zoomButton($0) }
                let _ = controller?.autoscaleAction = { viewport = content.autoscale(viewport) }
                let _ = controller?.resetAction = { viewport = viewport.fitted() }
                ZStack {
                    Canvas { context, size in
                        PlotDrawing(content: content, viewport: viewport, palette: PlotPalette(accent: accent, isDark: colorScheme == .dark),
                                    scale: displayScale, hover: hover ?? previewHover, box: boxMark ?? previewBox,
                                    measure: mode == .measure ? (measure ?? previewMeasure) : nil)
                            .draw(&context, size: size, cache: cache)
                    }
                    PlotInteractionLayer(layout: layout, mode: mode, events: events(layout))
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { plotSize = $0 }
                .onChange(of: mode) { _, new in if new != .measure { measure = nil } }
                // The levels of a measure are in the units of the axis: they mean nothing once the scale changes.
                .onChange(of: content.measureKey) { _, _ in measure = nil }
            }
        }
    }

    private var boxMark: PlotMeasure? { if case .box(let b)? = drag { return b } else { return nil } }

    private func transform(_ layout: PlotLayout) -> PlotTransform { PlotTransform(viewport: viewport, rect: layout.plot) }

    /// A click on a zoom button: around the centre of the plot, on the horizontal axis, with ⌥ on the vertical one, with ⇧ on both.
    private func zoomButton(_ factor: Double) {
        let layout = PlotLayout(size: plotSize)
        let anchor = CGPoint(x: layout.plot.midX, y: layout.plot.midY)
        let mods = PlotModifiers(NSEvent.modifierFlags)
        viewport = PlotGestures.zoom(viewport, axes: PlotGestures.axes(option: mods.option, shift: mods.shift), factor: factor, anchor: anchor, in: transform(layout))
    }

    // MARK: The events

    private func events(_ layout: PlotLayout) -> PlotPointerEvents {
        var e = PlotPointerEvents()
        e.hover = { p in if hover != p { hover = p } }
        e.scroll = { p, dx, dy, precise, mods in scroll(p, dx, dy, precise, mods, layout) }
        e.magnify = { p, amount, mods in
            viewport = PlotGestures.zoom(viewport, axes: PlotGestures.axes(option: mods.option, shift: mods.shift), factor: PlotGestures.factor(forMagnification: Double(amount)), anchor: p, in: transform(layout))
        }
        e.dragBegan = { p, mods in dragBegan(p, mods, layout) }
        e.dragChanged = { p, _ in dragChanged(p, layout) }
        e.dragEnded = { p in dragEnded(p, layout) }
        e.doubleClick = { p in
            switch layout.region(at: p) {
            case .plot: viewport = viewport.fitted(); measure = nil
            case .xAxis: viewport.x = viewport.x.fitted()
            case .yAxis: viewport = content.autoscale(viewport)
            case .outside: break
            }
        }
        return e
    }

    private func scroll(_ p: CGPoint, _ dx: CGFloat, _ dy: CGFloat, _ precise: Bool, _ mods: PlotModifiers, _ layout: PlotLayout) {
        let t = transform(layout)
        if mods.command || !precise {
            // A wheel, or ⌘ with a scroll that is precise (a trackpad, a Magic Mouse): zoom around the pointer. The axes are the
            // ones of the pinch and of the buttons: horizontal, with ⌥ vertical, with ⇧ both.
            let amount = Double(dy != 0 ? dy : dx) * (precise ? 1 : 4)
            viewport = PlotGestures.zoom(viewport, axes: PlotGestures.axes(option: mods.option, shift: mods.shift),
                                         factor: PlotGestures.factor(forScroll: amount), anchor: p, in: t)
        } else {
            viewport = PlotGestures.pan(viewport, byPixels: CGSize(width: dx, height: dy), in: t)
        }
    }

    private func dragBegan(_ p: CGPoint, _ mods: PlotModifiers, _ layout: PlotLayout) {
        switch layout.region(at: p) {
        case .plot:
            if mods.shift || mode == .pan { drag = .pan(last: p) }
            else if mode == .zoomBox { drag = .box(PlotMeasure(a: p, b: p)) }
            else {
                let a = content.measurePoint(at: p, transform(layout))
                measure = PlotSegment(x0: a.x, y0: a.y, x1: a.x, y1: a.y)
                drag = .measure
            }
        case .xAxis(let part): drag = .axis(isX: true, part: part, start: viewport.x, from: p)
        case .yAxis(let part): drag = .axis(isX: false, part: part, start: viewport.y, from: p)
        case .outside: drag = nil
        }
    }

    private func dragChanged(_ p: CGPoint, _ layout: PlotLayout) {
        switch drag {
        case .box(var b)?:
            b.b = clamp(p, layout.plot); drag = .box(b)
        case .measure?:
            let b = content.measurePoint(at: clamp(p, layout.plot), transform(layout))
            measure?.x1 = b.x; measure?.y1 = b.y
        case .pan(let last)?:
            viewport = PlotGestures.pan(viewport, byPixels: CGSize(width: p.x - last.x, height: p.y - last.y), in: transform(layout))
            drag = .pan(last: p)
        case .axis(let isX, let part, let start, let from)?:
            if isX {
                viewport.x = PlotGestures.axisDrag(start, part: part, delta: Double(p.x - from.x), length: Double(layout.xAxis.width))
            } else {
                viewport.y = PlotGestures.axisDrag(start, part: part, delta: Double(from.y - p.y), length: Double(layout.yAxis.height))
            }
        case nil: break
        }
    }

    private func dragEnded(_ p: CGPoint, _ layout: PlotLayout) {
        if case .box(let b)? = drag {
            viewport = PlotGestures.zoomBox(viewport, from: b.a, to: clamp(p, layout.plot), in: transform(layout))
        }
        // The measure stays (in the data) until the next measure or until the mode changes; the other drags end with the button.
        drag = nil
    }

    private func clamp(_ p: CGPoint, _ r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }
}
