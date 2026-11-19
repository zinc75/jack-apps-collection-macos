// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    static var appearance: AppearanceSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
}

@main
struct ZitaNetworkBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var appearance: AppearanceSettings

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
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
        let appearance = AppearanceSettings(appAccent: .blue, appColor: Color(red: 0.388, green: 0.4, blue: 0.945), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appearance)
                .appAccent(appearance)
                .frame(minWidth: 940, minHeight: 700)
        }
        .defaultSize(width: 1080, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .help) {}
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
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Zita Network Bridge") {
                    let credits = String(localized: "Interface non officielle de zita-njbridge, de Fons Adriaensen.\nPortage macOS et interface : Éric Bavu.\nLicence GPL, version 3.")
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    let upstream = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: "\(upstream) macOS Edition",
                        .version: "",
                        .credits: NSAttributedString(string: credits, attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: style,
                        ]),
                    ])
                }
            }
        }
    }
}
