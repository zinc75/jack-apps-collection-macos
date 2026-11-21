// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

/// The edit commands act on the text of a field while one is being edited, and on the matrix otherwise: they take the place of the
/// standard items of the menu, which a text field would otherwise use.
@MainActor
func editCommand(_ selector: Selector, _ onMatrix: () -> Void) {
    if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(selector, to: nil, from: nil) } else { onMatrix() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    static var appearance: AppearanceSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
}

@main
struct JackConvolverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var appearance: AppearanceSettings

    init() {
        CollectionMenus.disableSystemMenuAdditions()
        let env = ProcessInfo.processInfo.environment
        var keeps = true
        #if DEBUG
        // Debug aids (JACKCONVOLVER_*) must not touch what the person has set up.
        keeps = !env.keys.contains { $0.hasPrefix("JACKCONVOLVER_") }
        #endif
        let model = AppModel(defaults: keeps ? .standard : nil)
        _model = State(initialValue: model)
        AppDelegate.model = model

        var defaults = UserDefaults.standard
        #if DEBUG
        if env["JACKCONVOLVER_APPEARANCE"] != nil || env["JACKCONVOLVER_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackconvolver.debug.\(UUID().uuidString)") ?? defaults
            if let v = env["JACKCONVOLVER_APPEARANCE"] { defaults.set(v, forKey: AppearanceSettings.modeKey) }
            if let v = env["JACKCONVOLVER_ACCENT"] { defaults.set(v, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        // The violet of the application, as in the mockup: a little lighter on the dark look (#b07dfa) than on the light one (#9a5bf2),
        // so that it reads on both. A dynamic colour follows the look of the window by itself.
        let violet = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.690, green: 0.490, blue: 0.980, alpha: 1)
                : NSColor(srgbRed: 0.604, green: 0.357, blue: 0.949, alpha: 1)
        })
        let appearance = AppearanceSettings(appAccent: .purple, appColor: violet, defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appearance)
                .appAccent(appearance)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle configuration…") { model.showsNewConfiguration = true }.keyboardShortcut("n", modifiers: .command)
                Button("Ouvrir…") { model.openPanel() }.keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Enregistrer") { model.save() }.keyboardShortcut("s", modifiers: .command).disabled(!model.isOpen)
                Button("Enregistrer sous…") { model.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.isOpen)
            }
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .undoRedo) {
                Button(model.history.undoLabel.map { String(localized: "Annuler \($0)") } ?? String(localized: "Annuler")) { model.undo() }
                    .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo)
                Button(model.history.redoLabel.map { String(localized: "Rétablir \($0)") } ?? String(localized: "Rétablir")) { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Couper") { editCommand(#selector(NSText.cut(_:))) { model.cutSelection() } }.keyboardShortcut("x", modifiers: .command)
                Button("Copier") { editCommand(#selector(NSText.copy(_:))) { model.copySelection() } }.keyboardShortcut("c", modifiers: .command)
                Button("Coller") { editCommand(#selector(NSText.paste(_:))) { model.paste() } }.keyboardShortcut("v", modifiers: .command)
            }
            CommandGroup(replacing: .textEditing) {
                Button("Tout sélectionner") {
                    editCommand(#selector(NSText.selectAll(_:))) {
                        if let d = model.document { model.selection.selectAll(inputs: d.inputCount, outputs: d.outputCount) }
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {
                Button("Accueil") { model.page = .home }.keyboardShortcut("1", modifiers: .command)
                Divider()
                Button("Configuration RI") { model.page = .matrix }.keyboardShortcut("2", modifiers: .command).disabled(!model.isOpen)
                Button("Connexions") { model.page = .ports }.keyboardShortcut("3", modifiers: .command).disabled(!model.isOpen)
                Button("Lancement") { model.page = .launch }.keyboardShortcut("4", modifiers: .command).disabled(!model.isOpen)
                Button("Journal") { model.page = .log }.keyboardShortcut("5", modifiers: .command).disabled(!model.isOpen)
                Button("Affichage") { model.page = .display }.keyboardShortcut("6", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.page = .display }.keyboardShortcut(",", modifiers: .command)
            }
        }
        .commands {
            CommandMenu("Moteur") {
                Button(model.controller.isRunning ? "Arrêter" : "Lancer") { model.toggleRun() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.isOpen || (!model.controller.isRunning && model.hasErrors))
            }
        }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Jack Convolver",
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de jconvolver et fconvolver, de Fons Adriaensen."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 3.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "jconvolver-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Jack Convolver"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/jconvolver")!)
        }
    }
}
