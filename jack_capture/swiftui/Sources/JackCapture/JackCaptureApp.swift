// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

/// Removes the menus that the system adds by itself and that have nothing left in them (Format, once its commands are gone),
/// and holds back the quitting while a file is being written.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: RecorderModel?
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
        AppearanceChoice.saved.apply()
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

    private static var keepsSettings: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("JACKCAPTURE_AUTO") }
        #else
        return true
        #endif
    }

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let model = RecorderModel(defaults: Self.keepsSettings ? .standard : nil)
        _model = State(initialValue: model)
        AppDelegate.model = model
        #if DEBUG
        if ProcessInfo.processInfo.environment["JACKCAPTURE_FRESH"] != nil { model.pretendFirstLaunch() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
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
            CommandGroup(replacing: .help) {}
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Jack Capture") {
                    let credits = String(localized: "Interface non officielle de jack_capture, de Kjetil Matheussen.\nPortage macOS et interface : Éric Bavu.\nLicence GPL, version 2 ou ultérieure.")
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    // The version shown is the one of jack_capture, then "macOS Edition"; the build number is not shown.
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
    }
}
