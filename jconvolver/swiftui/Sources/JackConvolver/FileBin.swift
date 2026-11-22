// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SoundFileKit
import SwiftUI

/// The list beside the matrix: the sound files, each with its channels, and the pulse and the Hilbert filter. What is chosen in it is
/// dragged on the matrix.
struct FileBin: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    /// The row from which a shift-click extends.
    @State private var anchor = 0

    private struct Row: Identifiable {
        let id: String
        let items: [Placeable]
        let title: String
        let subtitle: String
        let file: BinFile?
        let isChild: Bool
        let expandable: Bool
        let usage: Int
    }

    /// The rows that are shown, in order: a file, its channels when it is open, then the filters.
    private var rows: [Row] {
        var out: [Row] = []
        let filter = model.binFilter.trimmingCharacters(in: .whitespaces)
        for file in model.binFiles where filter.isEmpty || file.name.localizedCaseInsensitiveContains(filter) {
            let channels = max(1, file.info.channels)
            let rate = (file.info.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)))
            let detail = String(localized: "\(channels) voie(s) · \(file.info.frames) éch. · \(rate) kHz")
            out.append(Row(id: file.path, items: (1...channels).map { .channel(path: file.path, channel: $0) }, title: file.name, subtitle: detail,
                           file: file, isChild: false, expandable: channels > 1, usage: model.uses(of: file)))
            if channels > 1, model.binExpanded.contains(file.path) {
                for c in 1...channels {
                    out.append(Row(id: "\(file.path)#\(c)", items: [.channel(path: file.path, channel: c)], title: String(localized: "voie \(c)"),
                                   subtitle: file.name, file: nil, isChild: true, expandable: false, usage: 0))
                }
            }
        }
        out.append(Row(id: "@dirac", items: [.dirac], title: String(localized: "Impulsion (Dirac)"), subtitle: "", file: nil, isChild: false, expandable: false, usage: 0))
        out.append(Row(id: "@hilbert", items: [.hilbert], title: String(localized: "Filtre de Hilbert"), subtitle: "", file: nil, isChild: false, expandable: false, usage: 0))
        return out
    }

    var body: some View {
        @Bindable var model = model
        let shown = rows
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fichiers de RI").font(.headline)
                Spacer()
                Menu {
                    Button("Ajouter des fichiers…") { model.chooseFilesForBin() }
                    Button("Ajouter un dossier…") { model.chooseFolderForBin() }
                } label: { Label("Ajouter", systemImage: "plus") }
                    .menuStyle(.button).fixedSize()
            }
            if model.fileURL != nil {
                Text(model.configDirectory).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            TextField("Filtrer par nom", text: $model.binFilter).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        if row.id == "@dirac" { Text("Filtres").font(.caption).foregroundStyle(.secondary).padding(.top, 10).padding(.horizontal, 6) }
                        rowView(row, index: index, all: shown)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Menu("Placer à la sélection") {
                    if model.placesOnAllChosenCells {
                        Button("Sur toutes les cases choisies") { model.placePicked(mode: .row) }
                            .disabled(!model.canPlaceOnChosenCells)
                    } else {
                        Button("En ligne") { model.placePicked(mode: .row) }
                        Button("En colonne") { model.placePicked(mode: .column) }
                        Button("En diagonale") { model.placePicked(mode: .diagonal) }
                    }
                }
                .disabled(model.picked.isEmpty)
                Text("Glissez sur la matrice. Plusieurs éléments : en ligne, ⌥ en colonne, ⇧ en diagonale ; ce qui dépasse la matrice n'est pas placé.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .blockBackground()
    }

    private func rowView(_ row: Row, index: Int, all: [Row]) -> some View {
        let selected = row.items.allSatisfy { model.picked.contains($0) }
        return HStack(spacing: 6) {
            if row.expandable {
                Button { toggleOpen(row) } label: {
                    Image(systemName: model.binExpanded.contains(row.id) ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).fontWeight(selected ? .semibold : .regular).lineLimit(1).truncationMode(.middle)
                if !row.subtitle.isEmpty { Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if row.usage > 0 { Text(verbatim: "×\(row.usage)").font(.caption).foregroundStyle(accent) }
        }
        .padding(.leading, row.isChild ? 18 : 0)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { click(row, index: index, all: all) }
        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("matrixPage"))
            .onChanged { value in
                if model.dragPointer == nil { model.beginItemDrag(row.items) }
                model.dragPointer = value.location
            }
            .onEnded { _ in model.endItemDrag() })
    }

    private func toggleOpen(_ row: Row) {
        if model.binExpanded.contains(row.id) { model.binExpanded.remove(row.id) } else { model.binExpanded.insert(row.id) }
    }

    /// A click chooses the row; command adds it or takes it out; shift chooses all the rows between this one and the last one.
    private func click(_ row: Row, index: Int, all: [Row]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            let items = Set(row.items)
            if items.isSubset(of: model.picked) { model.picked.subtract(items) } else { model.picked.formUnion(items) }
            anchor = index
        } else if flags.contains(.shift), anchor < all.count {
            var set = Set<Placeable>()
            for k in min(anchor, index)...max(anchor, index) { set.formUnion(all[k].items) }
            model.picked = set
        } else {
            model.picked = Set(row.items)
            anchor = index
        }
    }
}
