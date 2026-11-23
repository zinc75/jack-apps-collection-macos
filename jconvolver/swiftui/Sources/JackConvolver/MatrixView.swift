// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The page of the impulse responses: the list of files, the matrix, and what is selected.
struct MatrixView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.document == nil {
            SettingsPage {
                Text("Matrice de convolution").font(.title2).fontWeight(.semibold)
                Text("Aucune configuration ouverte.").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // The title and the line under it say what this view is for.
                VStack(alignment: .leading, spacing: 2) {
                    if model.viewMode == .table {
                        Text("Tableau des convolutions").font(.title2).fontWeight(.semibold)
                        Text("Chaque ligne correspond à une réponse impulsionnelle. Réglage rapide du gain et des paramètres temporels.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Matrice de convolution").font(.title2).fontWeight(.semibold)
                        Text("Glissez des réponses impulsionnelles (RI) sur les cases : chaque case relie une entrée à une sortie.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                LockBanner()
                if model.viewMode == .table {
                    ImpulseTable().frame(minHeight: 300)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        FileBin().frame(width: 270)
                        MatrixCanvas()
                    }
                    // The list and the matrix take the height there is; the detail under them keeps its own.
                    .frame(minHeight: 260, maxHeight: .infinity)
                    SelectionPanel().frame(height: 190)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "matrixPage")
            .overlay(alignment: .topLeading) { DraggedItemsBadge() }
        }
    }
}

/// What follows the pointer while impulse responses are dragged from the list to the matrix.
struct DraggedItemsBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        if let pointer = model.dragPointer {
            Group {
                if model.dropBlocked {
                    Label("Une seule réponse impulsionnelle sur plusieurs cases", systemImage: "nosign")
                } else {
                    Text("\(model.draggedItems.count) RI")
                }
            }
            .font(.callout.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(model.dropBlocked ? Color.red : accent, in: Capsule())
                .position(x: pointer.x + 24, y: pointer.y + 20)
                .allowsHitTesting(false)
        }
    }
}

/// The window toolbar on this page: the way to look at the impulse responses at the centre, then undo and redo, the actions on the
/// matrix, the help, and save. The state of JACK keeps its own place (`JackStatusPill`, in the toolbar of the window).
struct MatrixToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .principal) {
            // Two words: the native segmented control.
            Picker("Vue", selection: $model.viewMode) {
                Text("Matrice").tag(ViewMode.matrix)
                Text("Tableau").tag(ViewMode.table)
            }
            .pickerStyle(.segmented).labelsHidden().accentTint()
            .help("Voir les réponses impulsionnelles en matrice ou en tableau")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.undo() } label: { Label("Annuler", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Annuler")
            Button { model.redo() } label: { Label("Rétablir", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Rétablir")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showsResize = true } label: { Label("Entrées et sorties…", systemImage: "arrow.up.left.and.arrow.down.right") }
                .disabled(model.isLocked)
                .help("Changer le nombre d'entrées et de sorties")
            if model.mode == .realTime {
                Button { model.showsPortNames = true } label: { Label("Noms des ports JACK…", systemImage: "pencil") }
                    .disabled(model.isLocked)
                    .help("Noms des ports JACK")
            }
            // Not asked for confirmation: it can be undone.
            Button { model.clearAll() } label: { Label("Tout vider", systemImage: "trash") }
                .disabled((model.document?.placedPairs ?? 0) == 0 || model.isLocked)
                .help("Retirer toutes les réponses impulsionnelles de la matrice (annulable)")
        }
        ToolbarItem(placement: .primaryAction) {
            // Save: the picture and the word together (there is no picture for it that means it alone).
            Button { model.save() } label: { Label(model.savesAsNew ? "Enregistrer sous…" : "Enregistrer", systemImage: "square.and.arrow.down") }
                .labelStyle(.titleAndIcon)
                .disabled(!model.isEdited && !model.savesAsNew)
                .help(model.savesAsNew ? "Enregistrer sous… (⌘S)" : "Enregistrer (⌘S)")
        }
    }
}

/// In the top right corner of the matrix: what can be done with the mouse and the keys, written down.
struct GesturesButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.showsGestures = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 15)) }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Les gestes de la matrice")
            .keyboardShortcut("?", modifiers: .command)
            .padding(10)
    }
}

/// In the corner of the matrix, once its size is not the one that fills the block: back to that size.
struct ResetZoomButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.zoomIsManual, abs(model.cellSize - model.fitCellSize) >= 0.75 {
            Button { model.resetZoom() } label: { Label("Ajuster à la fenêtre", systemImage: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Remet la matrice à la taille qui remplit le bloc")
                .padding(10)
        }
    }
}
