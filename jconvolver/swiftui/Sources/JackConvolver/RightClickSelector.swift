// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// A right-click on a pair that is not selected selects it first, so that the menu acts on what was clicked, as in the Finder. The
/// menu of SwiftUI does not say where it was opened, so the pair under the pointer (kept by the matrix) is used.
@MainActor
enum RightClickSelector {
    private static var monitor: Any?

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            MainActor.assumeIsolated {
                if let pair = model.hoverPair, !model.selection.contains(pair) { model.selection.select(pair) }
            }
            return event
        }
    }
}
