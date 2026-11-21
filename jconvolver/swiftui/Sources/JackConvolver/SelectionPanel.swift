// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// Under the matrix: what is selected, and the impulse responses on it, with their gain, delay, start and length to change.
struct SelectionPanel: View {
    @Environment(AppModel.self) private var model

    private var entries: [(pair: ConvPair, index: Int, impulse: ConvImpulse)] {
        guard let document = model.document else { return [] }
        return model.selection.pairs.flatMap { pair in document.impulses(at: pair).enumerated().map { (pair, $0.offset, $0.element) } }
    }

    private var who: String {
        let s = model.selection, b = s.bounds
        if case .picked = s.shape { return String(localized: "\(s.count) cases choisies") }
        if s.isSingle { return "\(model.inputLabel(b.firstInput)) → \(model.outputLabel(b.firstOutput))" }
        let outputs = model.document?.outputCount ?? 0, inputs = model.document?.inputCount ?? 0
        if b.firstInput == b.lastInput, b.firstOutput == 0, b.lastOutput == outputs - 1, outputs > 1 {
            return String(localized: "\(model.inputLabel(b.firstInput)) → toutes les sorties")
        }
        if b.firstOutput == b.lastOutput, b.firstInput == 0, b.lastInput == inputs - 1, inputs > 1 {
            return String(localized: "Toutes les entrées → \(model.outputLabel(b.firstOutput))")
        }
        return String(localized: "\(b.lastInput - b.firstInput + 1) entrées × \(b.lastOutput - b.firstOutput + 1) sorties")
    }

    var body: some View {
        let list = entries
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(who).font(.headline)
                Text(list.isEmpty ? String(localized: "aucune RI") : String(localized: "\(list.count) RI")).foregroundStyle(.secondary)
                Spacer()
                if !list.isEmpty { Button("Vider", role: .destructive) { model.clearSelection() } }
            }
            if model.document?.placedPairs == 0 {
                Text("Aucune RI pour l'instant. Glissez des fichiers de la liste sur les cases.").foregroundStyle(.secondary)
            } else if list.isEmpty {
                Text("Pas de RI ici. Glissez-y un fichier de la liste.").foregroundStyle(.secondary)
            } else {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.prefix(60).enumerated()), id: \.offset) { _, entry in
                            ImpulseRow(pair: entry.pair, index: entry.index, impulse: entry.impulse)
                            Divider()
                        }
                        if list.count > 60 {
                            Text("… et \(list.count - 60) de plus. Sélectionnez une plage plus petite pour les voir.").font(.caption).foregroundStyle(.secondary).padding(8)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .blockBackground()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Entrée → sortie").frame(width: 150, alignment: .leading)
            Text("RI").frame(maxWidth: .infinity, alignment: .leading)
            Text("Gain (dB)").frame(width: 70, alignment: .trailing)
            Text("Retard").frame(width: 70, alignment: .trailing)
            Text("Début").frame(width: 70, alignment: .trailing)
            Text("Longueur").frame(width: 70, alignment: .trailing)
            Color.clear.frame(width: 22, height: 1)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

/// One impulse response of the selection, in a row.
struct ImpulseRow: View {
    @Environment(AppModel.self) private var model
    let pair: ConvPair
    let index: Int
    let impulse: ConvImpulse

    private var isFile: Bool { if case .file = impulse.source { return true } else { return false } }
    private var isCopy: Bool { if case .copy = impulse.source { return true } else { return false } }
    private var bad: Bool { model.pairsInError.contains(pair) }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(model.inputLabel(pair.input)) → \(model.outputLabel(pair.output))").lineLimit(1).frame(width: 150, alignment: .leading)
            HStack(spacing: 4) {
                Text(model.label(of: impulse)).foregroundStyle(bad ? Color.red : Color.primary).lineLimit(1).truncationMode(.middle)
                if bad { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ValueField(text: gainText, enabled: !isCopy) { commit(gain: $0) }
            ValueField(text: "\(impulse.delay)", enabled: !isCopy) { commit(delay: $0) }
            ValueField(text: "\(impulse.offset)", enabled: isFile) { commit(offset: $0) }
            ValueField(text: "\(impulse.length)", enabled: isFile) { commit(length: $0) }
            Button { model.edit(String(localized: "RI retirée")) { $0.remove(at: index, of: pair) } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 22).help("Vider cette RI")
        }
        .padding(.vertical, 3)
    }

    private var gainText: String { impulse.gainDB.isFinite ? impulse.gainDB.formatted(.number.precision(.fractionLength(1))) : "−∞" }

    private func change(_ label: String, _ edit: (inout ConvImpulse) -> Void) {
        var updated = impulse
        edit(&updated)
        model.edit(label) { $0.replace(updated, at: index, of: pair) }
    }

    private func commit(gain text: String) -> Bool {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite, v >= -200, v <= 60 else { return false }
        change(String(localized: "réglage du gain")) { $0.gainDB = v }
        return true
    }
    private func commit(delay text: String) -> Bool {
        guard let v = Int(text), v >= 0 else { return false }
        change(String(localized: "réglage du retard")) { $0.delay = v }
        return true
    }
    private func commit(offset text: String) -> Bool {
        guard let v = Int(text), v >= 0 else { return false }
        change(String(localized: "réglage du début")) { $0.offset = v }
        return true
    }
    private func commit(length text: String) -> Bool {
        guard let v = Int(text), v >= 0 else { return false }
        change(String(localized: "réglage de la longueur")) { $0.length = v }
        return true
    }
}

/// A number in a field of a row: the text is kept apart, so that it can be emptied, and the value is taken when it is validated. A value
/// that is not valid comes back to what it was.
struct ValueField: View {
    let text: String
    var enabled = true
    let commit: (String) -> Bool
    @State private var edited = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $edited)
            .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).monospacedDigit()
            .frame(width: 70).focused($focused).disabled(!enabled).opacity(enabled ? 1 : 0.35)
            .onAppear { edited = text }
            .onChange(of: text) { _, new in if !focused { edited = new } }
            .onSubmit { validate() }
            .onChange(of: focused) { _, now in if !now { validate() } }
    }

    private func validate() {
        if edited != text, !commit(edited) { edited = text }
    }
}
