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
            title: "Klick", subtitle: "Jack Apps Collection for macOS",
            about: AboutInfo(
                name: "Klick",
                // The version shown is the one of klick, then "macOS Edition"; the build number is not shown.
                version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                summary: String(localized: "Interface non officielle de klick, de Dominic Sacré."),
                lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 2 ou ultérieure.")],
                copyright: "© 2026 Éric Bavu",
                sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                licenseFile: "klick-COPYING.txt",
                licenseURL: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")),
            documentationTitle: String(localized: "Documentation Klick"),
            documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/klick")!,
            accent: .orange,
            accentColor: Color(red: 1.0, green: 0.42, blue: 0.10),
            additionalBackends: [BackendOffer(backend: JackBackend(), interface: JackInterface())],
            showsCommandLine: true,
            updateRepository: "zinc75/jack-apps-collection-macos", updateTagPrefix: "klick-v")
        _application = State(initialValue: KlickApplication(configuration: configuration))
    }

    var body: some Scene {
        KlickScene(application: application)
    }
}
