// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The same impulse responses as the matrix, as a table: one row for each, with the fields to change, and a row above them that sets a
/// field for all of them, or for the selection, at once.
struct ImpulseTable: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    private struct Entry: Identifiable {
        let pair: ConvPair
        let index: Int
        let impulse: ConvImpulse
        var id: String { "\(pair.input)-\(pair.output)-\(index)" }
    }

    private var entries: [Entry] {
        guard let document = model.document else { return [] }
        return document.content.impulses.keys.sorted().flatMap { pair in
            document.impulses(at: pair).enumerated().map { Entry(pair: pair, index: $0.offset, impulse: $0.element) }
        }
    }

    var body: some View {
        let rows = entries
        VStack(spacing: 0) {
            BulkRow()
            Divider()
            header
            Divider()
            if rows.isEmpty {
                Text("Aucune RI pour l'instant. Passez à la matrice et glissez-y des fichiers de la liste.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            row(entry, all: rows)
                            Divider()
                        }
                    }
                }
            }
        }
        .blockBackground()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Entrée").frame(width: 120, alignment: .leading)
            Text("Sortie").frame(width: 120, alignment: .leading)
            Text("RI").frame(maxWidth: .infinity, alignment: .leading)
            Text("Gain (dB)").frame(width: 70, alignment: .trailing)
            Text("Retard").frame(width: 70, alignment: .trailing)
            Text("Début").frame(width: 70, alignment: .trailing)
            Text("Longueur").frame(width: 70, alignment: .trailing)
            Color.clear.frame(width: 22, height: 1)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func row(_ entry: Entry, all: [Entry]) -> some View {
        let selected = model.selection.contains(entry.pair)
        return ImpulseRowFields(pair: entry.pair, index: entry.index, impulse: entry.impulse, showsPair: true)
            .padding(.horizontal, 12).padding(.vertical, 2)
            .background(selected ? accent.opacity(0.14) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { click(entry, all: all) }
    }

    /// A click chooses the row; command adds or takes out a pair; shift chooses the rows between this one and the last one, in the order
    /// of the table.
    private func click(_ entry: Entry, all: [Entry]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            model.selection.toggle(entry.pair)
        } else if flags.contains(.shift), let from = all.firstIndex(where: { $0.pair == model.selection.anchor }),
                  let to = all.firstIndex(where: { $0.id == entry.id }) {
            var seen = Set<ConvPair>(), list: [ConvPair] = []
            for e in all[min(from, to)...max(from, to)] where seen.insert(e.pair).inserted { list.append(e.pair) }
            model.selection.pick(list)
        } else {
            model.selection.select(entry.pair)
        }
    }
}

/// The row above the table: what the value typed under a column is applied to, and how.
struct BulkRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let total = model.document?.placedPairs ?? 0
        let chosen = model.selection.pairs.filter { !(model.document?.impulses(at: $0).isEmpty ?? true) }.count
        HStack(spacing: 10) {
            Text("Appliquer à").foregroundStyle(.secondary)
            Picker("Portée", selection: $model.bulkOnSelection) {
                Text("Toutes (\(total))").tag(false)
                Text("Sélection (\(chosen))").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            Picker("Façon", selection: $model.bulkShifts) {
                Text("Remplacer").tag(false)
                Text("Décaler").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            .help("Remplacer : la valeur prend la place de celle de chaque RI. Décaler : elle s'ajoute à celle de chaque RI, les écarts sont conservés.")
            Spacer()
            BulkInput(field: .gain)
            BulkInput(field: .delay)
            BulkInput(field: .offset)
            BulkInput(field: .length)
            Color.clear.frame(width: 22, height: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// A field of the row above the table: the value is applied when it is validated, and the field is emptied.
struct BulkInput: View {
    @Environment(AppModel.self) private var model
    let field: BulkField
    @State private var text = ""

    var body: some View {
        TextField("", text: $text, prompt: Text(verbatim: model.bulkShifts ? "±" : "—"))
            .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).monospacedDigit()
            .frame(width: 70)
            .onSubmit { apply() }
            .help(help)
    }

    private var help: LocalizedStringKey {
        switch field {
        case .gain: "Gain, en dB"
        case .delay: "Retard, en échantillons"
        case .offset: "Début, en échantillons (les fichiers seulement)"
        case .length: "Longueur, en échantillons (les fichiers seulement)"
        }
    }

    private func apply() {
        defer { text = "" }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return }
        model.bulkSet(field, value: value)
    }
}
