// SPDX-License-Identifier: MIT

import SwiftUI

/// Makes the window lay its toolbar out again. macOS lays a toolbar out once, and does not do it again when an inspector opens or closes, so
/// the items that belong to the side of the inspector stay where they were (over it, or cut off). It does when the window is resized: the
/// window is resized by a point and back at once, with no redraw in between. Put it in the background of the content of the window, with
/// `trigger` the state whose change needs a new layout (whether the inspector is shown, for instance); it also acts once when the window appears.
public struct ToolbarRelayout: NSViewRepresentable {
    var trigger: Bool

    public init(trigger: Bool) { self.trigger = trigger }

    public func makeNSView(context: Context) -> NSView { NSView() }

    public func updateNSView(_ view: NSView, context: Context) {
        // After the change has been laid out; also once, shortly after the window appears.
        DispatchQueue.main.async { Self.nudge(view.window) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Self.nudge(view.window) }
    }

    @MainActor static func nudge(_ window: NSWindow?) {
        guard let window, window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        var larger = frame
        larger.size.width += 2
        window.setFrame(larger, display: true)
        // In two turns of the run loop: the system joins two changes made in one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var back = window.frame
            back.size.width -= 2
            window.setFrame(back, display: true)
        }
    }
}
