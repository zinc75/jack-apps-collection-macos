// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

/// At the bottom of the sidebar: the configuration that is open (its name, whether it has changes that are not saved, what it holds) and a menu of
/// what can be done with its file; a magnifier opens the page of the configuration file.
struct FileCard: View {
    @Environment(AppModel.self) private var model
    @State private var hovered = false

    var body: some View {
        if model.isOpen {
            // The text has the whole width of the card; the controls are in a row of their own under it.
            VStack(alignment: .leading, spacing: 2) {
                // The card itself does nothing under the pointer (the name scrolls there): what opens the file is the magnifier.
                // No picture on the left: the text has the whole width, and is less often cut.
                VStack(alignment: .leading, spacing: 1) {
                    HoverScrollText(text: model.fileURL?.lastPathComponent ?? String(localized: "Sans titre"))
                        .font(.system(size: 13, weight: .bold))
                    if model.isEdited {
                        Text("Modifié").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    ForEach(summary, id: \.self) { line in
                        Text(verbatim: line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A hairline between what the card says and what can be done with the file.
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5).padding(.vertical, 3)
                // Both controls are the same kind of thing and look alike: a circled symbol of the same size and weight, grey at rest, plain under the
                // pointer. The first, the file, opens the page of the configuration file.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button { model.page = .config } label: { TraceGlyph(name: "doc.text") }
                        .buttonStyle(GlyphButtonStyle())
                        .help("Voir le fichier de configuration")
                    // The menu of the file: the same kind of control, with the three dots.
                    Menu {
                        Button("Renommer…") { model.renameFile() }.disabled(model.fileURL == nil || model.isLocked)
                        Divider()
                        Button(model.savesAsNew ? "Enregistrer sous…" : "Enregistrer") { model.save() }.disabled(!model.isEdited && !model.savesAsNew)
                        if !model.savesAsNew { Button("Enregistrer sous…") { model.save(asNew: true) } }
                        Divider()
                        Button("Afficher dans le Finder") { model.revealFile() }.disabled(model.fileURL == nil)
                        Button("Fermer") { model.closeConfiguration() }
                    } label: {
                        TraceGlyph(name: "ellipsis.circle")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(GlyphButtonStyle())
                .fixedSize()
                .help("Renommer, enregistrer, afficher dans le Finder, fermer")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hovered ? 0.11 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovered = $0 }
            .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
        }
    }

    /// What the configuration holds, in words, one thing a line: the inputs, the outputs, the impulse responses.
    private var summary: [String] {
        guard let d = model.document else { return [] }
        let inputs = d.inputCount == 1 ? String(localized: "1 entrée") : String(localized: "\(d.inputCount) entrées")
        let outputs = d.outputCount == 1 ? String(localized: "1 sortie") : String(localized: "\(d.outputCount) sorties")
        let responses = d.placedPairs == 0 ? String(localized: "aucune réponse impulsionnelle")
            : d.placedPairs == 1 ? String(localized: "1 réponse impulsionnelle") : String(localized: "\(d.placedPairs) réponses impulsionnelles")
        return [inputs, outputs, responses]
    }
}

/// A line of text that is cut in the middle when it does not fit, and that scrolls under the pointer to be read to its end.
struct HoverScrollText: View {
    let text: String
    @State private var hovered = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var shift: CGFloat = 0

    private var overflow: CGFloat { max(textWidth - containerWidth, 0) }

    private var scrolling: Bool { hovered && overflow > 1 }

    var body: some View {
        // The line as it is at rest (cut in the middle) always takes its place: it gives the width that there is, which the scrolling text, wider,
        // must not change. The text that scrolls is drawn over it, and cut by the frame.
        Text(verbatim: text).lineLimit(1).truncationMode(.middle)
            .opacity(scrolling ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
            .overlay(alignment: .leading) {
                if scrolling { Text(verbatim: text).fixedSize().offset(x: shift) }
            }
            .clipped()
            // The width the text would have in full.
            .background {
                Text(verbatim: text).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            }
        .onHover { hovered = $0 }
        .task(id: hovered) {
            guard hovered else { shift = 0; return }
            // A moment to see where it starts, then to the end at a pace that can be read.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, overflow > 1 else { return }
            withAnimation(.linear(duration: max(0.6, Double(overflow) / 45))) { shift = -overflow }
        }
    }
}
