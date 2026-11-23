// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

extension FocusedValues {
    /// The session of the window that has the focus: what the commands of the menus act on.
    @Entry var session: AppModel?
}

/// The commands that act on the window that has the focus. With no window in front they act on a session that nothing shows, so that they do nothing
/// (and what opens files goes to a new session).
struct PlayCommands: Commands {
    let hub: AppHub
    @FocusedValue(\.session) private var focused: AppModel?
    private var model: AppModel { focused ?? hub.sessionHub.idleSession }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle session") { hub.requestNewSession(from: focused) }.keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Ouvrir…") { if let focused { focused.chooseFile() } else { hub.chooseFiles() } }.keyboardShortcut("o", modifiers: .command)
            Button("Ajouter à la liste…") { model.addFiles() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(focused == nil)
            Divider()
            Button("Ouvrir une liste…") { model.openPlaylistFile() }.disabled(focused == nil)
            Button("Enregistrer la liste…") { model.savePlaylist() }.disabled(focused == nil || model.playlist.playlist.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .textFormatting) {}
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
}
