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

/// The command line that the engine runs, to read and to copy.
struct CommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let line = model.displayedCommand?.displayString ?? ""
        VStack(alignment: .leading, spacing: 14) {
            Text("Ligne de commande générée").font(.title3).fontWeight(.semibold)
            Text("Collée dans un terminal, elle lance le moteur de la même façon.").font(.callout).foregroundStyle(.secondary)
            Text(line)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color(white: 0.9))
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
            Text(model.problems.isEmpty ? "Prêt à lancer" : "\(model.problems.count) à régler").font(.title3).fontWeight(.semibold)
            ScrollView { ProblemList() }.frame(maxHeight: 380)
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 560)
    }
}
