// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import SwiftUI

/// The gestures of the matrix, written down: opened by the "?" of the page, and from the Help menu.
struct GesturesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let keys: [String]
        let text: LocalizedStringKey
        var id: String { keys.joined() }
    }

    private let choosing: [Row] = [
        Row(keys: ["Clic"], text: "Choisir une case"),
        Row(keys: ["Glisser"], text: "Choisir une plage de cases"),
        Row(keys: ["⇧", "Clic"], text: "Étendre la sélection jusqu'à cette case"),
        Row(keys: ["⌘", "Clic"], text: "Ajouter ou retirer une case"),
        Row(keys: ["Clic sur un nom"], text: "Choisir toute la ligne ou toute la colonne"),
        Row(keys: ["⌘", "A"], text: "Tout choisir"),
    ]
    private let placing: [Row] = [
        Row(keys: ["Glisser"], text: "Poser sur la matrice ce qui est choisi dans la liste de fichiers"),
        Row(keys: ["⌥", "Glisser"], text: "… en colonne (les voies suivent les entrées)"),
        Row(keys: ["⇧", "Glisser"], text: "… en diagonale"),
        Row(keys: ["Double-clic"], text: "Poser ce qui est choisi dans la liste sur une case vide"),
        Row(keys: ["Clic droit"], text: "Le menu d'une case : copier, coller, placer, détail…"),
    ]
    private let editing: [Row] = [
        Row(keys: ["⌘", "C"], text: "Copier les RI des cases choisies"),
        Row(keys: ["⌘", "V"], text: "Coller à partir de la première case choisie"),
        Row(keys: ["⌫"], text: "Retirer les RI des cases choisies"),
        Row(keys: ["⌘", "Z"], text: "Annuler (⇧ ⌘ Z : rétablir)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gestes de la matrice").font(.title3).fontWeight(.semibold)
            group("Choisir", choosing)
            group("Placer", placing)
            group("Modifier", editing)
            Text("Plusieurs cases choisies : une seule RI (fichier mono, Dirac, Hilbert) peut être posée sur toutes à la fois.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction).accentTint() }
        }
        .padding(22).frame(width: 560)
    }

    private func group(_ title: LocalizedStringKey, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(rows) { row in
                    GridRow {
                        HStack(spacing: 4) { ForEach(row.keys, id: \.self) { KeyCap(text: $0) } }
                            .frame(width: 190, alignment: .leading)
                        Text(row.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A key, or a mouse action, as a small cap.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
    }
}

/// On an empty matrix: a light veil over the matrix, with a card in the middle that says what to do first. Clicks and drops go through
/// the veil; only the buttons of the card take them.
struct EmptyMatrixHint: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    private let width: CGFloat = 330

    var body: some View {
        if let document = model.document, document.placedPairs == 0, model.dragPointer == nil {
            ZStack {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                card
            }
            .transition(.opacity)
        }
    }

    private var card: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
                Image(systemName: "waveform.path").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(spacing: 4) {
                Text("Aucune RI pour l'instant").font(.headline)
                Text("Glissez un fichier de la liste sur une case de la matrice : chaque case relie une entrée à une sortie.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button { model.showsGestures = true } label: { Label("Voir les gestes", systemImage: "questionmark.circle") }
                .buttonStyle(.bordered).controlSize(.regular)
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .frame(width: width)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
