// SPDX-License-Identifier: MIT

import SwiftUI

extension View {
    /// The inspector of a window as a panel of glass that floats at the right edge: rounded, with a hairline and a shadow, sliding in. On macOS 26
    /// it is glass (a material before). In a narrow window it floats over the view; with `docked` it keeps its room instead, and the view gives it the
    /// width it needs (animated), so that the panel looks the same in both and the plot is not hidden when the window has the room.
    public func plotOverlayInspector<Panel: View>(isPresented: Bool, docked: Bool = false, width: CGFloat = 280,
                                                  @ViewBuilder panel: () -> Panel) -> some View {
        let content = panel()
        return ZStack(alignment: .trailing) {
            self.padding(.trailing, isPresented && docked ? width + 10 : 0)
            if isPresented {
                content
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .modifier(PlotPanelGlass())
                    .padding(10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
        .animation(.easeOut(duration: 0.2), value: docked)
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
