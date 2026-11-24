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
    /// Something from the Finder is above the list.
    @State private var targeted = false
    /// The file whose impulse response is looked at in a popover: the row it comes from, its path and its channel.
    @State private var preview: Preview?

    private struct Preview: Equatable { var rowID: String; var path: String; var channel: Int? }

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
            let detail = channels == 1
                ? String(localized: "\(channels) voie · \(file.info.frames) éch. · \(rate) kHz")
                : String(localized: "\(channels) voies · \(file.info.frames) éch. · \(rate) kHz")
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
            }
            if model.fileURL != nil {
                Text(model.configDirectory).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            TextField("Filtrer par nom", text: $model.binFilter).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if model.binFiles.isEmpty { EmptyBinCard().padding(.bottom, 6) }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        if row.id == "@dirac" { Text("Filtres").font(.caption).foregroundStyle(.secondary).padding(.top, 10).padding(.horizontal, 6) }
                        rowView(row, index: index, all: shown)
                    }
                }
            }
            footer
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .blockBackground()
        // Sound files and folders dropped from the Finder go into the list.
        .dropDestination(for: URL.self) { urls, _ in
            model.addFilesAndFolders(urls)
            return !urls.isEmpty
        } isTargeted: { targeted = $0 }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }

    /// The bar under the list, which does not scroll: "+" to add (one panel for files and folders, which can also be dropped here from the
    /// Finder), and a menu of what else can be done with the list.
    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 4) {
                Button { model.chooseForBin() } label: { Self.footerSymbol("plus.circle") }
                    .buttonStyle(GlyphButtonStyle())
                    .help("Ajouter des fichiers audio ou un dossier…")
                    .accessibilityLabel("Ajouter des fichiers audio ou un dossier")
                Button { model.removeFromBin(pickedPaths) } label: { Self.footerSymbol("minus.circle") }
                    .buttonStyle(GlyphButtonStyle())
                    .disabled(model.removableFromBin(pickedPaths).isEmpty)
                    .help("Retirer de la liste les fichiers choisis (ils restent sur le disque ; ceux que la matrice utilise restent dans la liste)")
                    .accessibilityLabel("Retirer de la liste les fichiers choisis")
                Spacer()
                Menu {
                    Button("Ajouter des fichiers…") { model.chooseFilesForBin() }
                    Button("Ajouter un dossier…") { model.chooseFolderForBin() }
                    Divider()
                    Button("Retirer de la liste") { model.removeFromBin(pickedPaths) }
                        .disabled(model.removableFromBin(pickedPaths).isEmpty)
                    Button("Relire le dossier de la configuration") { model.reloadBin() }
                        .disabled(model.fileURL == nil)
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting(pickedFiles) }
                        .disabled(pickedFiles.isEmpty)
                } label: {
                    Self.footerSymbol("ellipsis.circle")
                }
                // The style of a button, not the one of a menu of the system, which draws its symbol at its own size: both symbols are the same.
                .menuStyle(.button).buttonStyle(GlyphButtonStyle()).menuIndicator(.hidden).fixedSize()
                .help("Plus d'actions sur la liste")
                .accessibilityLabel("Plus d'actions sur la liste")
            }
        }
    }

    /// A symbol of the bar under the list: the same size for every one.
    private static func footerSymbol(_ name: String) -> some View {
        Image(systemName: name).resizable().scaledToFit().frame(width: 16, height: 16)
    }

    /// The paths of the files of what is chosen in the list.
    private var pickedPaths: [String] {
        Set(model.picked.compactMap { item -> String? in if case .channel(let path, _) = item { path } else { nil } }).sorted()
    }

    /// The files of what is chosen in the list.
    private var pickedFiles: [URL] { pickedPaths.map { URL(fileURLWithPath: $0) } }

    /// Opens the plots of the file of a row, from its channel when the row is one (all the channels when it is the file).
    private func openPreview(_ row: Row) {
        guard case .channel(let path, let channel)? = row.items.first else { return }
        preview = Preview(rowID: row.id, path: path, channel: row.isChild ? channel : nil)
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
                HStack(spacing: 2) {
                    Text(row.title).fontWeight(selected ? .semibold : .regular).lineLimit(1).truncationMode(.middle)
                    // The way in to the plots of the file, next to its name (the menu of a right click has it too).
                    if let item = row.items.first, case .channel = item {
                        Button { openPreview(row) } label: { InspectSymbol(size: 14) }
                            .buttonStyle(GlyphButtonStyle())
                            .help("Inspecter la réponse impulsionnelle : forme d'onde, spectre et phase")
                            .accessibilityLabel("Inspecter la réponse impulsionnelle")
                            .layoutPriority(1)
                    }
                }
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
        .contextMenu {
            if case .channel(let path, _)? = row.items.first {
                Button("Inspecter la réponse impulsionnelle…") { openPreview(row) }
                Button("Retirer de la liste") { model.removeFromBin(model.picked.contains(row.items[0]) ? pickedPaths : [path]) }
                    .disabled(model.removableFromBin(model.picked.contains(row.items[0]) ? pickedPaths : [path]).isEmpty)
            }
        }
        .popover(isPresented: Binding(get: { preview?.rowID == row.id }, set: { if !$0, preview?.rowID == row.id { preview = nil } }), arrowEdge: .trailing) {
            if let preview, preview.rowID == row.id { FilePreview(path: preview.path, channel: preview.channel).environment(model) }
        }
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

/// When the list has no sound file: what to do first, with the two ways to add some.
struct EmptyBinCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: "waveform.badge.plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            }
            Text("Aucun fichier de RI").font(.headline)
            Text("Ajoutez vos fichiers audio de RI, ou un dossier qui les contient : ils peupleront la matrice.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                Button { model.chooseFolderForBin() } label: { Label("Ajouter un dossier…", systemImage: "folder.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).accentTint()
                Button { model.chooseFilesForBin() } label: { Label("Ajouter des fichiers…", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Text("ou glissez-les ici depuis le Finder").font(.caption).foregroundStyle(.secondary)
            }
        }
              .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
