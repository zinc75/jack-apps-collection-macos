// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).

import SwiftUI
import KlickUI
import KlickJack
import AppearanceKit

/// Klick of the Jack Apps Collection: the application of the family with the JACK backend, chosen next to CoreAudio on the page
/// "Sortie". Its name, its colour (a warm orange, the orange of the system is yellower) and its backends; all the rest is in KlickUI.
@main
struct KlickApp: App {
    @NSApplicationDelegateAdaptor(KlickAppDelegate.self) private var appDelegate
    @State private var application: KlickApplication

    init() {
        let configuration = KlickConfiguration(
            title: "Klick", subtitle: "Jack Apps Collection for macOS", accent: .orange,
            accentColor: Color(red: 1.0, green: 0.42, blue: 0.10),
            additionalBackends: [BackendOffer(backend: JackBackend(), interface: JackInterface())])
        _application = State(initialValue: KlickApplication(configuration: configuration))
    }

    var body: some Scene {
        KlickScene(application: application)
    }
}
