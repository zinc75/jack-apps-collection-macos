// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit
import AppearanceKit

/// Removes the menus that the system adds by itself and that have nothing left in them (Format, once its commands are gone),
/// and holds back the quitting while a file is being written.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: RecorderModel?
    /// The look chosen by the user; given by the application before the first window, applied at launch.
    static var appearance: AppearanceSettings?
    private var pending = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting stops the recording first, and waits for jack_capture to close the file: it would otherwise
    /// be cut (its output pipes close with the application, and it would die writing to them).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.isBusy else { return .terminateNow }
        if model.isWriting {
            let alert = NSAlert()
            alert.messageText = String(localized: "Un enregistrement est en cours")
            alert.informativeText = String(localized: "Arrêter l'enregistrement et quitter ? Le fichier est refermé proprement.")
            alert.addButton(withTitle: String(localized: "Arrêter et quitter"))
            alert.addButton(withTitle: String(localized: "Annuler"))
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        model.stopForQuit { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.appearance?.applyAppearance()
        prune()
        NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { [weak self] _ in
            self?.schedule()
        }
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [self] in
            pending = false
            prune()
        }
    }

    private func prune() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items.dropFirst() {
            guard let submenu = item.submenu else { continue }
            if submenu.items.allSatisfy({ $0.isSeparatorItem || $0.isHidden }) { main.removeItem(item) }
        }
    }
}

@main
struct JackCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The settings of the last session come back; a development run that forces settings does not keep them.
    @State private var model: RecorderModel
    @State private var appearance: AppearanceSettings

    private static var keepsSettings: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("JACKCAPTURE_AUTO") }
        #else
        return true
        #endif
    }

    init() {
        CollectionMenus.disableSystemMenuAdditions()
        let model = RecorderModel(defaults: Self.keepsSettings ? .standard : nil)
        _model = State(initialValue: model)
        AppDelegate.model = model
        #if DEBUG
        if ProcessInfo.processInfo.environment["JACKCAPTURE_FRESH"] != nil { model.pretendFirstLaunch() }
        #endif

        // The colour of the application is a red a little deeper than the one of the system, so that it is not taken for the red of
        // the record button or of an alert; the look is dark until the user says otherwise.
        var defaults = UserDefaults.standard
        #if DEBUG
        // Development aids: JACKCAPTURE_APPEARANCE=dark|system|light and JACKCAPTURE_ACCENT=app|system|blue|purple|pink|red|orange|green
        // set the look of the run, in a store of their own that is not kept.
        let environment = ProcessInfo.processInfo.environment
        if environment["JACKCAPTURE_APPEARANCE"] != nil || environment["JACKCAPTURE_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackcapture.debug.\(UUID().uuidString)") ?? defaults
            if let value = environment["JACKCAPTURE_APPEARANCE"] { defaults.set(value, forKey: AppearanceSettings.modeKey) }
            if let value = environment["JACKCAPTURE_ACCENT"] { defaults.set(value, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        let appearance = AppearanceSettings(appAccent: .red, appColor: Color(red: 0.90, green: 0.17, blue: 0.24), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(appearance)
                .appAccent(appearance)
                // The window is never smaller than 940 x 850 (the toolbar adds 52 points to the height below).
                .frame(minWidth: 940, minHeight: 798)
        }
        .defaultSize(width: 1120, height: 850)
        .windowResizability(.contentMinSize)
        .commands {
            // Nothing to open, save, print, find, format or look up: only what the application uses stays.
            // Cut, copy and paste remain for the text fields.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
        }
        .commands {
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {
                Button("Enregistrement") { model.view = .recording }.keyboardShortcut("1", modifiers: .command)
                Divider()
                Button("Voies") { model.view = .channels }.keyboardShortcut("2", modifiers: .command)
                Button("Fichier") { model.view = .file }.keyboardShortcut("3", modifiers: .command)
                Button("Démarrage et arrêt") { model.view = .startStop }.keyboardShortcut("4", modifiers: .command)
                Button("Avancé") { model.view = .advanced }.keyboardShortcut("5", modifiers: .command)
                Button("Affichage") { model.view = .display }.keyboardShortcut("6", modifiers: .command)
            }
            // The settings of the system convention (command comma) are the page "Affichage".
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.view = .display }.keyboardShortcut(",", modifiers: .command)
            }
        }
        .commands {
            CommandMenu("Enregistrement") {
                Button(model.phase.showsStopSymbol ? "Arrêter" : "Enregistrer") {
                    #if DEBUG
                    model.trace("menu action fired")
                    #endif
                    model.toggleRecording()
                }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Jack Capture",
                    // The version shown is the one of the program, then "macOS Edition"; the build number is not shown.
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de jack_capture, de Kjetil Matheussen."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 2 ou ultérieure.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "jack_capture-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Jack Capture"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/jack_capture")!)
        }
    }
}
