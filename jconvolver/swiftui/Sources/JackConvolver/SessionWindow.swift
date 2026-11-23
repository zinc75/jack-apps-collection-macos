// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

/// The window of a session: the content of the application for one configuration. It tells the application how to open another window, and the
/// menus which session has the focus.
struct SessionWindow: View {
    let hub: AppHub
    let appearance: AppearanceSettings
    @State private var session: AppModel
    @Environment(\.openWindow) private var openWindow

    init(hub: AppHub, id: UUID, appearance: AppearanceSettings) {
        self.hub = hub
        self.appearance = appearance
        // The session of this window: made the first time, found again after.
        _session = State(initialValue: hub.session(for: id))
    }

    var body: some View {
        ContentView()
            .environment(session)
            .environment(appearance)
            .appAccent(appearance)
            .focusedSceneValue(\.session, session)
            .frame(minWidth: 1070, minHeight: 830)
            .onAppear { hub.openWindowAction = { openWindow(value: $0) } }
    }
}
