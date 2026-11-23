// SPDX-License-Identifier: MIT

import SwiftUI

extension View {
    /// The inspector of a window as a panel of glass that floats at the right edge: rounded, with a hairline and a shadow, sliding in. On macOS 26
    /// it is glass (a material before). In a narrow window it floats over the view; with `docked` it keeps its room instead, and the view gives it the
    /// width it needs (animated), so that the panel looks the same in both and the plot is not hidden when the window has the room.
    /// `bottomInset` stops a floating panel that far above the bottom of the view, to leave free what is under the plot (the sliders of a region,
    /// the minimap): the view says how far, from the bottom of its plot area. `onOutsideClick` is called when the floating panel is shown and a click
    /// lands elsewhere in the window under the toolbar (the click still goes where it was meant to): the panel closes itself, as a popover does.
    /// `topInset` and `trailingInset` place a floating panel from the top and from the right edge of the view (10 points by default), to line it up
    /// with the container of the plot and leave what is above it free (a title, a legend).
    public func plotOverlayInspector<Panel: View>(isPresented: Bool, docked: Bool = false, width: CGFloat = 280, bottomInset: CGFloat = 0,
                                                  topInset: CGFloat? = nil, trailingInset: CGFloat? = nil,
                                                  onOutsideClick: (() -> Void)? = nil, @ViewBuilder panel: () -> Panel) -> some View {
        let content = panel()
        return ZStack(alignment: .trailing) {
            self.padding(.trailing, isPresented && docked ? width + 10 : 0)
            if isPresented {
                content
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .modifier(PlotPanelGlass())
                    .background(PlotOutsideClickMonitor(isActive: !docked && onOutsideClick != nil) { onOutsideClick?() })
                    .padding(EdgeInsets(top: docked ? 10 : max(topInset ?? 10, 0), leading: 10, bottom: 10 + (docked ? 0 : max(bottomInset, 0)),
                                        trailing: docked ? 10 : max(trailingInset ?? 10, 0)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
        .animation(.easeOut(duration: 0.2), value: docked)
        .animation(.easeOut(duration: 0.2), value: bottomInset)
        .animation(.easeOut(duration: 0.2), value: topInset)
    }
}

/// The surface of a floating panel.
private struct PlotPanelGlass: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }
}

extension View {
    /// Reports the width of the window that holds the view, as the window has it: not the width of the view, which an inspector of the system
    /// takes room from when it is open. What decides between the system's inspector and the floating one must not depend on which of the two is
    /// shown, or the choice would flip as the panel opens.
    public func plotWindowWidth(_ width: @escaping (CGFloat) -> Void) -> some View {
        background(PlotWindowWidthReader(report: width))
    }
}

private struct PlotWindowWidthReader: NSViewRepresentable {
    let report: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { Anchor(coordinator: context.coordinator) }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.report = report; context.coordinator.send() }

    @MainActor final class Coordinator {
        var report: ((CGFloat) -> Void)?
        weak var window: NSWindow?
        private var observer: NSObjectProtocol?

        func attach(_ window: NSWindow?) {
            guard window !== self.window else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            self.window = window
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.send() }
            }
            send()
        }

        func send() {
            guard let window else { return }
            let width = window.frame.width
            DispatchQueue.main.async { [weak self] in self?.report?(width) }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    private final class Anchor: NSView {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); coordinator.attach(window) }
    }
}

/// Calls `onOutsideClick` when the mouse goes down in the window, under the toolbar, outside the view it is behind. The event is not consumed.
/// A click in another window (a popover, a menu) or in the toolbar (where the button of the inspector is) does not count.
private struct PlotOutsideClickMonitor: NSViewRepresentable {
    var isActive: Bool
    var onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { Anchor(coordinator: context.coordinator) }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.handler = onOutsideClick
        context.coordinator.anchor = view
        context.coordinator.setActive(isActive)
    }

    @MainActor final class Coordinator {
        var handler: (() -> Void)?
        weak var anchor: NSView?
        private var monitor: Any?
        /// The width, in points, of the strip along the edges of the window where a click does not close the panel.
        private static let edgeMargin: CGFloat = 12

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    MainActor.assumeIsolated { self?.handle(event) }
                    return event
                }
            } else if !active {
                remove()
            }
        }

        private func handle(_ event: NSEvent) {
            guard let anchor, let window = anchor.window, event.window === window, window.contentLayoutRect.contains(event.locationInWindow) else { return }
            // The border of the window, where it is taken to be resized, is a safe zone: a click there is not one in the window.
            let inner = NSRect(origin: .zero, size: window.frame.size).insetBy(dx: Self.edgeMargin, dy: Self.edgeMargin)
            guard inner.contains(event.locationInWindow) else { return }
            // Taking a handle of a region (the truncation of a response, say) is working on the plot, with the panel beside it: it stays.
            if PlotHandles.hit(event.locationInWindow, in: window) { return }
            if !anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                DispatchQueue.main.async { [weak self] in self?.handler?() }
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    private final class Anchor: NSView {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { coordinator.remove() } }
    }
}

/// A view that has handles under the pointer: a click on one of them does not close a floating panel.
@MainActor protocol PlotHandleHitTesting: AnyObject {
    func hitsHandle(atWindowPoint p: NSPoint) -> Bool
}

@MainActor enum PlotHandles {
    private static let views = NSHashTable<NSView>.weakObjects()

    static func register(_ view: NSView & PlotHandleHitTesting) { views.add(view) }

    static func hit(_ point: NSPoint, in window: NSWindow) -> Bool {
        views.allObjects.contains { view in
            guard view.window === window, let tester = view as? PlotHandleHitTesting else { return false }
            return tester.hitsHandle(atWindowPoint: point)
        }
    }
}

/// Marks the whole area behind it as handles of a region (the bar of a range): clicks on it do not close a floating panel.
struct PlotHandleArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Area() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Area: NSView, PlotHandleHitTesting {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { PlotHandles.register(self) }
        }
        func hitsHandle(atWindowPoint p: NSPoint) -> Bool { bounds.contains(convert(p, from: nil)) }
    }
}
