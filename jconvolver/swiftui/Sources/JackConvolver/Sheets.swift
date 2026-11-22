// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The number of inputs and outputs of a new configuration.
struct NewConfigurationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var inputs = 8
    @State private var outputs = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nouvelle configuration").font(.title3).fontWeight(.semibold)
                Text("Le nombre de voies. Les réponses impulsionnelles (RI) se placent ensuite, en les glissant sur les cases.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Entrées")
                    NumberField(label: "Entrées", value: $inputs, range: 1...128)
                    Stepper("", value: $inputs, in: 1...128).labelsHidden()
                }
                GridRow {
                    Text("Sorties")
                    NumberField(label: "Sorties", value: $outputs, range: 1...128)
                    Stepper("", value: $outputs, in: 1...128).labelsHidden()
                }
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Créer") { model.newConfiguration(inputs: inputs, outputs: outputs); dismiss() }
                    .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 440)
    }
}

/// Changes the number of inputs and outputs of the configuration that is open.
struct ResizeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var inputs = 1
    @State private var outputs = 1

    /// How many impulse responses go away with the pairs that leave the matrix.
    private var lost: Int {
        guard let document = model.document else { return 0 }
        var after = document
        after.resize(inputs: inputs, outputs: outputs)
        return document.content.impulses.values.reduce(0) { $0 + $1.count } - after.content.impulses.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Entrées et sorties").font(.title3).fontWeight(.semibold)
                Text("Le nombre de voies de la matrice. Les noms et les RI des voies qui restent sont gardés.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Entrées")
                    NumberField(label: "Entrées", value: $inputs, range: 1...128)
                    Stepper("", value: $inputs, in: 1...128).labelsHidden()
                }
                GridRow {
                    Text("Sorties")
                    NumberField(label: "Sorties", value: $outputs, range: 1...128)
                    Stepper("", value: $outputs, in: 1...128).labelsHidden()
                }
            }
            if lost > 0 {
                Label(lost == 1 ? "1 RI sera retirée." : "\(lost) RI seront retirées.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.alert)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Appliquer") {
                    model.edit(String(localized: "nombre d'entrées et de sorties")) { $0.resize(inputs: inputs, outputs: outputs) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
                .disabled(inputs == model.document?.inputCount && outputs == model.document?.outputCount)
            }
        }
        .padding(22).frame(width: 440)
        .onAppear { inputs = model.document?.inputCount ?? 1; outputs = model.document?.outputCount ?? 1 }
    }
}

/// The command line that the engine runs, to read and to copy.
struct CommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let line = model.displayedCommand?.displayString ?? ""
        VStack(alignment: .leading, spacing: 14) {
            Text("Ligne de commande générée").font(.title3).fontWeight(.semibold)
            Text("Collée dans un terminal, elle lance le moteur de la même façon.").font(.callout).foregroundStyle(.secondary)
            // The terminal view is dark in both appearances, with the colours of a shell.
            Text(CommandHighlighter.attributed(line))
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            HStack {
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line, forType: .string)
                }
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 620)
    }
}

/// What is to settle before the engine can start.
struct ProblemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.problems.isEmpty ? String(localized: "Prêt à lancer") : model.problems.count == 1 ? String(localized: "1 problème à régler") : String(localized: "\(model.problems.count) problèmes à régler")).font(.title3).fontWeight(.semibold)
            ScrollView { ProblemList() }.frame(maxHeight: 380)
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 560)
    }
}

/// The names of the ports of the engine: the ones JACK shows, and the labels of the rows and columns of the matrix. An empty field
/// keeps the name the engine gives by itself (`in-1`, `out-1`...). A name is unique among the inputs and the outputs together.
struct PortNamesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: [String] = []
    @State private var outputs: [String] = []
    @State private var inputPrefix = "in"
    @State private var outputPrefix = "out"

    private func effective(_ names: [String], _ prefix: String) -> [String] {
        names.enumerated().map { $0.element.trimmingCharacters(in: .whitespaces).isEmpty ? "\(prefix)-\($0.offset + 1)" : $0.element.trimmingCharacters(in: .whitespaces) }
    }

    /// The names that appear twice, in the inputs and the outputs together.
    private var duplicates: Set<String> {
        let all = effective(inputs, "in") + effective(outputs, "out")
        var seen = Set<String>(), dup = Set<String>()
        for n in all where !seen.insert(n).inserted { dup.insert(n) }
        return dup
    }

    var body: some View {
        let dup = duplicates
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Noms des ports JACK").font(.title3).fontWeight(.semibold)
                Text("Ces noms sont ceux des ports JACK (/input/name et /output/name) et des lignes et colonnes de la matrice. Chaque nom est unique, entrées et sorties confondues. Un champ vide garde le nom par défaut.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 18) {
                column("Entrées", $inputs, prefix: $inputPrefix, defaultPrefix: "in", dup: dup)
                column("Sorties", $outputs, prefix: $outputPrefix, defaultPrefix: "out", dup: dup)
            }
            if !dup.isEmpty {
                Label("Ces noms sont portés plusieurs fois : \(dup.sorted().joined(separator: ", ")).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.alert).font(.callout)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { apply(); dismiss() }.buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction).disabled(!dup.isEmpty)
            }
        }
        .padding(22).frame(width: 640)
        .onAppear {
            inputs = model.document?.inputs.map { $0.name ?? "" } ?? []
            outputs = model.document?.outputs.map { $0.name ?? "" } ?? []
        }
    }

    private func column(_ title: LocalizedStringKey, _ names: Binding<[String]>, prefix: Binding<String>, defaultPrefix: String, dup: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                TextField("Préfixe", text: prefix).textFieldStyle(.roundedBorder).frame(width: 80)
                Button("Numéroter") {
                    let p = prefix.wrappedValue.trimmingCharacters(in: .whitespaces)
                    names.wrappedValue = names.wrappedValue.indices.map { "\(p.isEmpty ? defaultPrefix : p)\($0 + 1)" }
                }
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(names.wrappedValue.indices, id: \.self) { i in
                        let shown = names.wrappedValue[i].trimmingCharacters(in: .whitespaces)
                        HStack(spacing: 6) {
                            Text(verbatim: "\(i + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
                            TextField("\(defaultPrefix)-\(i + 1)", text: names[i]).textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dup.contains(shown.isEmpty ? "\(defaultPrefix)-\(i + 1)" : shown) ? Color.alert : .clear, lineWidth: 1))
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .frame(maxWidth: .infinity)
    }

    private func apply() {
        let ins = inputs, outs = outputs
        model.edit(String(localized: "changement des noms des ports")) { d in
            for (i, n) in ins.enumerated() where i < d.inputCount { let t = n.trimmingCharacters(in: .whitespaces); d.content.inputs[i].name = t.isEmpty ? nil : t }
            for (o, n) in outs.enumerated() where o < d.outputCount { let t = n.trimmingCharacters(in: .whitespaces); d.content.outputs[o].name = t.isEmpty ? nil : t }
        }
    }
}
