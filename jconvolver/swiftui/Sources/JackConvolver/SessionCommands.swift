// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import SwiftUI

extension FocusedValues {
    /// The session of the window that has the focus: what the commands of the menus act on.
    @Entry var session: AppModel?
}

/// The commands that act on the window that has the focus. With no window in front they act on a session that nothing shows, so that they do nothing.
struct SessionCommands: Commands {
    let hub: AppHub
    @FocusedValue(\.session) private var focused: AppModel?
    private var model: AppModel { focused ?? hub.sessionHub.idleSession }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle configuration…") { model.showsNewConfiguration = true }.keyboardShortcut("n", modifiers: .command)
            Button("Ouvrir…") { model.openPanel() }.keyboardShortcut("o", modifiers: .command)
    }
    CommandGroup(replacing: .saveItem) {
        // Closes the configuration, not the window (the red button closes that): back to the home page, after asking about what is not saved.
        // With no configuration open it is the window that closes, as in the other applications.
        Button("Fermer") { if model.isOpen { model.closeConfiguration() } else { NSApp.keyWindow?.performClose(nil) } }
            .keyboardShortcut("w", modifiers: .command)
        Divider()
        Button(model.savesAsNew ? "Enregistrer sous…" : "Enregistrer") { model.save() }.keyboardShortcut("s", modifiers: .command).disabled(!model.isOpen)
        Button("Enregistrer sous…") { model.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.isOpen)
        Button("Exporter en version portable…") { model.showsPortable = true }.disabled(!model.canExportPortable)
        Divider()
        Button("Renommer…") { model.renameFile() }.disabled(!model.isOpen || model.fileURL == nil || model.isLocked)
        Button("Afficher dans le Finder") { model.revealFile() }.disabled(model.fileURL == nil)
    }
    CommandGroup(replacing: .importExport) {}
    CommandGroup(replacing: .undoRedo) {
        // Not disabled with the history: a text being edited has its own undo, which the menu cannot know about.
        Button(model.undoLabel.map { String(localized: "Annuler \($0)") } ?? String(localized: "Annuler")) { undoCommand(redo: false) { model.undo() } }
            .keyboardShortcut("z", modifiers: .command)
        Button(model.redoLabel.map { String(localized: "Rétablir \($0)") } ?? String(localized: "Rétablir")) { undoCommand(redo: true) { model.redo() } }
            .keyboardShortcut("z", modifiers: [.command, .shift])
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
        Button("Convolutions") { model.page = .matrix }.keyboardShortcut("2", modifiers: .command).disabled(!model.isOpen)
        Button("Analyse") { model.page = .impulse }.keyboardShortcut("3", modifiers: .command).disabled(!model.isOpen)
        Button("Connexions") { model.page = .ports }.keyboardShortcut("4", modifiers: .command).disabled(!model.isOpen || model.mode == .file)
        Button("Lancement") { model.page = .launch }.keyboardShortcut("5", modifiers: .command).disabled(!model.isOpen || model.mode == .file)
        Button("Fichier de configuration") { model.page = .config }.keyboardShortcut("6", modifiers: .command).disabled(!model.isOpen)
        Button("Journal") { model.page = .log }.keyboardShortcut("7", modifiers: .command).disabled(!model.isOpen)
        Button("Affichage") { model.page = .display }.keyboardShortcut("8", modifiers: .command)
    }
    CommandGroup(replacing: .appSettings) {
        Button("Réglages…") { model.page = .display }.keyboardShortcut(",", modifiers: .command)
    }
    }
}

/// The menus of the matrix and of the engine, for the window that has the focus.
struct SelectionCommands: Commands {
    let hub: AppHub
    @FocusedValue(\.session) private var focused: AppModel?
    private var model: AppModel { focused ?? hub.sessionHub.idleSession }

    var body: some Commands {
        CommandMenu("Sélection") {
            Button("Toute la ligne") {
                if let d = model.document { model.selection.selectInput(model.selection.bounds.firstInput, outputs: d.outputCount) }
            }.disabled(!model.isOpen)
            Button("Toute la colonne") {
                if let d = model.document { model.selection.selectOutput(model.selection.bounds.firstOutput, inputs: d.inputCount) }
            }.disabled(!model.isOpen)
            Button("Tout ce qui utilise ce fichier") {
                model.selectPairsUsingFile(of: ConvPair(input: model.selection.bounds.firstInput, output: model.selection.bounds.firstOutput))
            }.disabled(!model.isOpen)
            Divider()
            // The way to place without the mouse: what is chosen in the list goes on the chosen cell.
            if model.placesOnAllChosenCells {
                Button("Placer sur toutes les cases choisies") { model.placePicked(mode: .row) }
                    .disabled(!model.isOpen || !model.canPlaceOnChosenCells)
            } else {
                Menu("Placer ici ce qui est choisi dans la liste") {
                    Button("En ligne") { model.placePicked(mode: .row) }
                    Button("En colonne") { model.placePicked(mode: .column) }
                    Button("En diagonale") { model.placePicked(mode: .diagonal) }
                }
                .disabled(!model.isOpen || model.picked.isEmpty)
            }
            Divider()
            Button("Retirer les réponses impulsionnelles de la sélection") { model.clearSelection() }.disabled(!model.canCopy)
    }
    CommandGroup(after: .help) {
        Divider()
        Button("Gestes de la matrice") { model.page = .matrix; model.showsGestures = true }.disabled(!model.isOpen)
    }
    CommandMenu("Moteur") {
        Button(model.controller.isRunning ? "Arrêter" : "Lancer") { model.toggleRun() }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.isOpen || (!model.controller.isRunning && model.hasErrors))
    }
    }
}
