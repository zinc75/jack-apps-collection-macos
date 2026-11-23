// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// Under the matrix: what is selected, and the impulse responses on it, with their gain, delay, start and length to change.
struct SelectionPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

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
                AdaptiveText(long: list.isEmpty ? String(localized: "aucune réponse impulsionnelle") : list.count == 1 ? String(localized: "1 réponse impulsionnelle") : String(localized: "\(list.count) réponses impulsionnelles"),
                             short: list.isEmpty ? String(localized: "aucune RI") : String(localized: "\(list.count) RI"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if !list.isEmpty { Button("Vider", role: .destructive) { model.clearSelection() } }
            }
            if model.document?.placedPairs == 0 {
                Text("Aucune réponse impulsionnelle pour l'instant. Glissez des fichiers de la liste sur les cases.").foregroundStyle(.secondary)
            } else if list.isEmpty {
                Text("Pas de réponse impulsionnelle ici. Glissez-y un fichier de la liste.").foregroundStyle(.secondary)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("matrixPage")) } action: { model.selectionPanelFrame = $0 }
        .blockBackground()
        .overlay {
            // Something dragged above the panel: it is a place to drop it, and the cells it would go to are lit in the matrix.
            if model.dropOnPanel {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(model.dropBlocked ? Color.red : accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Entrée → sortie").frame(width: 150, alignment: .leading)
            AdaptiveText(long: String(localized: "Réponse impulsionnelle"), short: String(localized: "RI")).frame(maxWidth: .infinity, alignment: .leading)
            Text("Gain (dB)").frame(width: 70, alignment: .trailing)
            Text("Retard").frame(width: 70, alignment: .trailing)
            Text("Début").frame(width: 70, alignment: .trailing)
            Text("Longueur").frame(width: 70, alignment: .trailing)
            Color.clear.frame(width: 52, height: 1)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

/// One impulse response of the selection, in a row.
struct ImpulseRow: View {
    let pair: ConvPair
    let index: Int
    let impulse: ConvImpulse
    var body: some View { ImpulseRowFields(pair: pair, index: index, impulse: impulse, showsPair: false) }
}

/// The fields of an impulse response: where it is, what it is, its gain, delay, start and length, and the button that removes it.
/// The table shows the input and the output apart; the panel under the matrix shows them together.
struct ImpulseRowFields: View {
    @Environment(AppModel.self) private var model
    let pair: ConvPair
    let index: Int
    let impulse: ConvImpulse
    var showsPair = false

    private var isFile: Bool { if case .file = impulse.source { return true } else { return false } }
    private var isCopy: Bool { if case .copy = impulse.source { return true } else { return false } }
    private var bad: Bool { model.impulsesInError.contains(ConvProblem.Place(pair: pair, index: index)) }

    var body: some View {
        HStack(spacing: 8) {
            if showsPair {
                Text(model.inputLabel(pair.input)).lineLimit(1).frame(width: 120, alignment: .leading)
                Text(model.outputLabel(pair.output)).lineLimit(1).frame(width: 120, alignment: .leading)
            } else {
                Text("\(model.inputLabel(pair.input)) → \(model.outputLabel(pair.output))").lineLimit(1).frame(width: 150, alignment: .leading)
            }
            HStack(spacing: 4) {
                Text(model.label(of: impulse)).foregroundStyle(bad ? Color.red : Color.primary).lineLimit(1).truncationMode(.middle)
                if bad { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ValueField(text: gainText, enabled: !isCopy) { commit(gain: $0) }
            ValueField(text: "\(impulse.delay)", enabled: !isCopy) { commit(delay: $0) }
            ValueField(text: "\(impulse.offset)", enabled: isFile) { commit(offset: $0) }
            ValueField(text: "\(impulse.length)", enabled: isFile) { commit(length: $0) }
            Button { model.detail = DetailTarget(pair: pair, index: index) } label: {
                InspectSymbol()
            }
                .buttonStyle(GlyphButtonStyle()).opacity(isFile ? 1 : 0.25).disabled(!isFile)
                .help("Inspecter la réponse impulsionnelle : forme d'onde, spectre et analyse")
            Button { model.edit(String(localized: "RI retirée")) { $0.remove(at: index, of: pair) } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 22).help("Vider cette réponse impulsionnelle")
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
        guard var v = Int(text), v >= 0 else { return false }
        // Not longer than what is left of the file after the start.
        if case .file(let file, _) = impulse.source,
           let info = model.catalog.info(at: ConvConfig.path(of: file, directory: impulse.directory, configDirectory: model.configDirectory)) {
            v = min(v, max(Int(info.frames) - impulse.offset, 0))
        }
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
            .onChange(of: text) { _, new in edited = new }
            .onSubmit { validate() }
            .onChange(of: focused) { _, now in if !now { validate() } }
    }

    private func validate() {
        if edited != text, !commit(edited) { edited = text }
    }
}

/// "Look at this impulse response": its line in a viewfinder, both symbols of the system.
struct InspectSymbol: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Image(systemName: "viewfinder").font(.system(size: size, weight: .regular))
            Image(systemName: "waveform.path.ecg").font(.system(size: size * 0.55, weight: .bold))
        }
    }
}

/// A button that is a symbol (the detail of an impulse response, the "+" of the list of files): grey at rest, plain (white in a dark appearance) and a little larger when the
/// pointer is over it.
struct GlyphButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Face<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let lit = hovering && isEnabled
            label
                .foregroundStyle(lit ? Color.primary : Color.secondary)
                .frame(width: 26, height: 24)
                .scaleEffect(lit ? (isPressed ? 1.04 : 1.16) : 1)
                .animation(.easeOut(duration: 0.12), value: lit)
                .animation(.easeOut(duration: 0.08), value: isPressed)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// A text in two forms: the long one where there is room for it, the short one (an abbreviation) where there is not.
struct AdaptiveText: View {
    let long: String
    let short: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: long).lineLimit(1)
            Text(verbatim: short).lineLimit(1)
        }
    }
}
