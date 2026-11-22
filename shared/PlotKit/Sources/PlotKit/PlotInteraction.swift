// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// The modifier keys that matter to the plot.
struct PlotModifiers: Equatable {
    var command = false, option = false, shift = false
    init(_ flags: NSEvent.ModifierFlags = []) {
        command = flags.contains(.command); option = flags.contains(.option); shift = flags.contains(.shift)
    }
}

/// What the pointer does, given to the plot by the layer that receives the events. Points are in the view, from its top left.
struct PlotPointerEvents {
    var hover: (CGPoint?) -> Void = { _ in }
    var scroll: (_ at: CGPoint, _ dx: CGFloat, _ dy: CGFloat, _ precise: Bool, _ modifiers: PlotModifiers) -> Void = { _, _, _, _, _ in }
    var magnify: (_ at: CGPoint, _ amount: CGFloat, _ modifiers: PlotModifiers) -> Void = { _, _, _ in }
    var dragBegan: (_ at: CGPoint, _ modifiers: PlotModifiers) -> Void = { _, _ in }
    var dragChanged: (_ at: CGPoint, _ modifiers: PlotModifiers) -> Void = { _, _ in }
    var dragEnded: (_ at: CGPoint) -> Void = { _ in }
    var doubleClick: (_ at: CGPoint) -> Void = { _ in }
}

/// Receives the events of the pointer over the plot: the wheel and the trackpad, the pinch, the buttons, the movement.
/// SwiftUI gestures cannot tell a wheel from a trackpad or read the modifier keys of a scroll, which a plot needs.
/// A place of the plot where the pointer has a cursor of its own (the handles of a region).
struct PlotCursorRect: Equatable {
    enum Kind: Equatable { case resizeHorizontal, grab }
    var rect: CGRect
    var kind: Kind

    /// The part of the rectangle that is in the plot, or nil when there is none (a handle that the zoom took out of the view, a value
    /// that is not a number): AppKit raises an exception for a cursor rectangle that is empty or not finite.
    func clipped(to plot: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        let r = rect.intersection(plot)
        guard !r.isNull, !r.isEmpty, r.origin.x.isFinite, r.origin.y.isFinite, r.width.isFinite, r.height.isFinite else { return nil }
        return r
    }
}

struct PlotInteractionLayer: NSViewRepresentable {
    var layout: PlotLayout
    var mode: PlotMode
    var events: PlotPointerEvents
    var cursors: [PlotCursorRect] = []

    func makeNSView(context: Context) -> PlotInteractionView { PlotInteractionView() }

    func updateNSView(_ view: PlotInteractionView, context: Context) {
        view.events = events
        view.mode = mode
        view.cursors = cursors
        if view.layout != layout { view.layout = layout }
    }
}

final class PlotInteractionView: NSView {
    var events = PlotPointerEvents()
    var mode: PlotMode = .zoomBox { didSet { if mode != oldValue { window?.invalidateCursorRects(for: self) } } }
    var layout = PlotLayout(size: .zero) { didSet { window?.invalidateCursorRects(for: self) } }
    var cursors: [PlotCursorRect] = [] { didSet { if cursors != oldValue { window?.invalidateCursorRects(for: self) } } }

    private var dragStart: CGPoint?
    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) { events.hover(point(event)) }
    override func mouseEntered(with event: NSEvent) { events.hover(point(event)) }
    override func mouseExited(with event: NSEvent) { events.hover(nil) }

    override func scrollWheel(with event: NSEvent) {
        events.scroll(point(event), event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas, PlotModifiers(event.modifierFlags))
    }

    override func magnify(with event: NSEvent) {
        events.magnify(point(event), event.magnification, PlotModifiers(event.modifierFlags))
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        dragStart = p
        dragging = false
        if event.clickCount == 2 { events.doubleClick(p); dragStart = nil }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = point(event)
        if !dragging {
            guard hypot(p.x - start.x, p.y - start.y) >= 3 else { return }
            dragging = true
            events.dragBegan(start, PlotModifiers(event.modifierFlags))
        }
        events.dragChanged(p, PlotModifiers(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { events.dragEnded(point(event)) }
        dragging = false
        dragStart = nil
    }

    override func resetCursorRects() {
        let plotCursor: NSCursor = mode == .pan ? .openHand : .crosshair
        addCursorRect(layout.plot, cursor: plotCursor)
        for c in cursors {
            guard let r = c.clipped(to: layout.plot) else { continue }
            addCursorRect(r, cursor: c.kind == .resizeHorizontal ? .resizeLeftRight : .openHand)
        }
        let x = layout.xAxis, y = layout.yAxis
        let ends = x.width * AxisPart.endShare, endsY = y.height * AxisPart.endShare
        addCursorRect(CGRect(x: x.minX, y: x.minY, width: ends, height: x.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: x.maxX - ends, y: x.minY, width: ends, height: x.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: x.minX + ends, y: x.minY, width: x.width - 2 * ends, height: x.height), cursor: .openHand)
        addCursorRect(CGRect(x: y.minX, y: y.minY, width: y.width, height: endsY), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: y.minX, y: y.maxY - endsY, width: y.width, height: endsY), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: y.minX, y: y.minY + endsY, width: y.width, height: y.height - 2 * endsY), cursor: .openHand)
    }
}
