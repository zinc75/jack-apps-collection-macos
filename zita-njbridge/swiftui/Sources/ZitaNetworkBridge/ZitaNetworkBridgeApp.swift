// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    static var appearance: AppearanceSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.appearance?.applyAppearance()
        #if DEBUG
        // Debug aids: ZITABRIDGE_MENUDUMP=<file> writes the titles of the menus, ZITABRIDGE_ABOUT=<file> opens the About panel
        // and writes the number of its window.
        let env = ProcessInfo.processInfo.environment
        if let path = env["ZITABRIDGE_MENUDUMP"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                var out = ""
                for top in NSApp.mainMenu?.items ?? [] {
                    out += "# \(top.title)\n"
                    for item in top.submenu?.items ?? [] { out += item.isSeparatorItem ? "  ---\n" : "  \(item.title)  [\(item.keyEquivalent)]  \(item.action.map(NSStringFromSelector) ?? "-")\n" }
                }
                try? out.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["ZITABRIDGE_ABOUT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSApp.mainMenu?.item(at: 0)?.submenu?.performActionForItem(at: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if let panel = NSApp.windows.first(where: { $0 is NSPanel }) {
                        try? "\(panel.frame) visible=\(panel.isVisible) \(panel.windowNumber)".write(toFile: path + ".info", atomically: true, encoding: .utf8)
                        try? "\(panel.windowNumber)".write(toFile: path, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        #endif
    }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
}

@main
struct ZitaNetworkBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var appearance: AppearanceSettings

    init() {
        CollectionMenus.disableSystemMenuAdditions()
        let env = ProcessInfo.processInfo.environment
        var keeps = true
        #if DEBUG
        keeps = !env.keys.contains { $0.hasPrefix("ZITABRIDGE_") }
        #endif
        let model = AppModel(defaults: keeps ? .standard : nil)
        _model = State(initialValue: model)
        AppDelegate.model = model

        var defaults = UserDefaults.standard
        #if DEBUG
        if env["ZITABRIDGE_APPEARANCE"] != nil || env["ZITABRIDGE_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "zita.debug.\(UUID().uuidString)") ?? defaults
            if let v = env["ZITABRIDGE_APPEARANCE"] { defaults.set(v, forKey: AppearanceSettings.modeKey) }
            if let v = env["ZITABRIDGE_ACCENT"] { defaults.set(v, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        // The accent of the application is an indigo (provisional, as in the mockup).
        let appearance = AppearanceSettings(appAccent: .blue, appColor: Color(red: 0.369, green: 0.608, blue: 1.0), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appearance)
                .appAccent(appearance)
                // As JackMate, whose minimum was sized for a small laptop screen: 720 high.
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1100, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {
                Button("Liaison") { model.page = .link }.keyboardShortcut("1", modifiers: .command)
                Divider()
                Button("Réseau") { model.page = .network }.keyboardShortcut("2", modifiers: .command)
                Button("Voies") { model.page = .lanes }.keyboardShortcut("3", modifiers: .command)
                Button("Flux") { model.page = .flow }.keyboardShortcut("4", modifiers: .command)
                Button("Affichage") { model.page = .display }.keyboardShortcut("5", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.page = .display }.keyboardShortcut(",", modifiers: .command)
            }
        }
        .commands {
            CommandMenu("Liaison") {
                Button(model.controller.anyArmedRuns ? "Arrêter" : "Démarrer") {
                    if model.needsConfiguration { model.page = .network } else { model.controller.toggleAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.controller.armedDirections.isEmpty)
            }
        }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Zita Network Bridge",
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de zita-njbridge, de Fons Adriaensen."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 3 ou ultérieure.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "zita-njbridge-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Zita Network Bridge"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/zita-njbridge")!)
        }
    }
}
