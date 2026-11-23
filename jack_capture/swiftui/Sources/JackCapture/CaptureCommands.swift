// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import AppearanceKit
import JackCaptureKit
import SessionKit
import SwiftUI

extension FocusedValues {
    /// The session of the window that has the focus: what the commands of the menus act on.
    @Entry var session: RecorderModel?
}

/// The sessions of the application: their windows, the icon of the menu bar and the Dock are the business of `SessionKit`.
typealias CaptureSessions = SessionHub<RecorderModel>

extension SessionHub where S == RecorderModel {
    /// ⌘N. A session that records: a new one, at once. A session that is stopped and has something in it (settings that are not the defaults, a recording
    /// that is done): the person is asked whether to open a new session or to start this one over. A session with nothing in it is used as it is.
    func requestNewSession(from session: RecorderModel?) {
        guard let session, window(of: session) != nil else { newSession(); return }
        if session.isBusy { newSession(); return }
        guard session.hasPreparedSettings else { showWindow(of: session); return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Cette session a déjà des réglages.")
        alert.informativeText = String(localized: "Ouvrir une nouvelle session, ou repartir de zéro dans celle-ci ?")
        alert.addButton(withTitle: String(localized: "Nouvelle session"))
        alert.addButton(withTitle: String(localized: "Remplacer cette session"))
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: newSession()
        case .alertSecondButtonReturn: session.resetToDefaults()
        default: break
        }
    }
}

/// The commands that act on the window that has the focus. With no window in front they act on a session that nothing shows, so that they do nothing.
struct CaptureCommands: Commands {
    let hub: CaptureSessions
    @FocusedValue(\.session) private var focused: RecorderModel?
    private var model: RecorderModel { focused ?? hub.idleSession }

    var body: some Commands {
        // Nothing to open, save, print, find, format or look up: only what the application uses stays.
        // Cut, copy and paste remain for the text fields.
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle session") { hub.requestNewSession(from: focused) }.keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
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
