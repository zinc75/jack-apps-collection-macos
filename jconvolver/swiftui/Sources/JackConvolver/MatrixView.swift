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
                Text("Configuration des RI").font(.title2).fontWeight(.semibold)
                Text("Aucune configuration ouverte.").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration des RI").font(.title2).fontWeight(.semibold)
                    Text("Glissez des réponses impulsionnelles (RI) sur les cases : chaque case relie une entrée à une sortie.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                MatrixToolbar()
                if model.viewMode == .table {
                    ImpulseTable().frame(minHeight: 300)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        FileBin().frame(width: 270)
                        VStack(alignment: .leading, spacing: 6) {
                            MatrixCanvas()
                            MatrixFooter()
                        }
                    }
                    .frame(minHeight: 260)
                    SelectionPanel().frame(height: 190)
                }
            }
            .padding(24)
        }
    }
}

/// The actions of the page: empty the matrix, undo and redo, save.
struct MatrixToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Picker("Vue", selection: $model.viewMode) {
                Label("Matrice", systemImage: "square.grid.3x3").tag(ViewMode.matrix)
                Label("Tableau", systemImage: "tablecells").tag(ViewMode.table)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            Text(verbatim: summary).foregroundStyle(.secondary).padding(.leading, 6)
            Spacer()
            if model.mode == .realTime {
                Button { model.showsPortNames = true } label: { Label("Noms des ports JACK…", systemImage: "pencil") }
            }
            Button { model.clearAll() } label: { Label("Tout vider", systemImage: "trash") }
                .disabled((model.document?.placedPairs ?? 0) == 0)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Annuler").keyboardShortcut("z", modifiers: .command)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Rétablir").keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Enregistrer") { model.save() }
                .buttonStyle(.borderedProminent).accentTint().disabled(!model.isEdited)
        }
    }

    private var summary: String {
        guard let d = model.document else { return "" }
        return String(localized: "\(d.placedPairs) RI · \(d.inputCount) entrées × \(d.outputCount) sorties")
    }
}

/// Under the matrix: what is under the pointer, and the size of the cells.
struct MatrixFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Text(verbatim: hovered).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("Zoom").font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.cellSize, in: 10...44).frame(width: 140).controlSize(.small).accentTint()
        }
    }

    private var hovered: String {
        guard let pair = model.hoverPair, let document = model.document else {
            return String(localized: "Clic : case · glisser : plage · ⇧ étend · ⌘ ajoute · ⌫ vide")
        }
        let impulses = document.impulses(at: pair)
        let place = "\(model.inputLabel(pair.input)) → \(model.outputLabel(pair.output))"
        guard let first = impulses.first else { return place + " · " + String(localized: "vide") }
        let gain = first.gainDB.isFinite ? first.gainDB.formatted(.number.precision(.fractionLength(1))) + " dB" : "−∞ dB"
        return place + " · " + model.label(of: first) + " · " + gain + (impulses.count > 1 ? " (+\(impulses.count - 1))" : "")
    }
}
