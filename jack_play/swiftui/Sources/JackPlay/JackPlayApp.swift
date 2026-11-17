// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    static var appearance: AppearanceSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }

    /// A file dropped on the icon, or opened from the Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.model?.open(urls)
    }
}

@main
struct JackPlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var appearance: AppearanceSettings

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let env = ProcessInfo.processInfo.environment
        var keeps = true
        #if DEBUG
        keeps = !env.keys.contains { $0.hasPrefix("JACKPLAY_") }
        #endif
        let model = AppModel(defaults: keeps ? .standard : nil)
        _model = State(initialValue: model)
        AppDelegate.model = model

        var defaults = UserDefaults.standard
        #if DEBUG
        if env["JACKPLAY_APPEARANCE"] != nil || env["JACKPLAY_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackplay.debug.\(UUID().uuidString)") ?? defaults
            if let v = env["JACKPLAY_APPEARANCE"] { defaults.set(v, forKey: AppearanceSettings.modeKey) }
            if let v = env["JACKPLAY_ACCENT"] { defaults.set(v, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        // The accent of the application is a turquoise green.
        let appearance = AppearanceSettings(appAccent: .green, appColor: Color(red: 0.067, green: 0.639, blue: 0.576), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appearance)
                .appAccent(appearance)
                .frame(minWidth: 900, minHeight: 640)
        }
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir…") { model.chooseFile() }.keyboardShortcut("o", modifiers: .command)
                Button("Ajouter à la liste…") { model.addFiles() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Ouvrir une liste…") { model.openPlaylistFile() }
                Button("Enregistrer la liste…") { model.savePlaylist() }.disabled(model.playlist.playlist.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(replacing: .toolbar) {
                Button("Lecture") { model.page = .play }.keyboardShortcut("1", modifiers: .command)
                Button("Liste de lecture") { model.page = .playlist }.keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Sorties") { model.page = .outputs }.keyboardShortcut("3", modifiers: .command)
                Button("Boucle et transport") { model.page = .loop }.keyboardShortcut("4", modifiers: .command)
                Button("Avancé") { model.page = .advanced }.keyboardShortcut("5", modifiers: .command)
                Button("Affichage") { model.page = .display }.keyboardShortcut("6", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.page = .display }.keyboardShortcut(",", modifiers: .command)
            }
        }
        .commands {
            CommandMenu("Lecture") {
                Button(model.player.isPlaying ? "Pause" : "Lecture") { model.player.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Retour au début") { model.player.stop() }.keyboardShortcut(".", modifiers: .command)
                Divider()
                Button("Fichier suivant") { model.playlist.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!model.playlist.hasNext || model.player.mode == .followTransport)
                Button("Fichier précédent") { model.playlist.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(model.playlist.playlist.current == nil || model.player.mode == .followTransport)
            }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Jack Play") {
                    let credits = String(localized: "Interface non officielle de jack_play (rju-play de Rohan Drape).\nPortage macOS et interface : Éric Bavu.\nLicence GPL, version 3.")
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
