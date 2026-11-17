// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackPlayKit
import MatrixKit
import SwiftUI
import WaveformKit

/// The list of files: who plays, who comes next, the order, what to repeat.
struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Int?
    /// The row that is dragged to change the order, and how far the pointer has gone down (up when negative).
    @State private var dragged: Int?
    @State private var dragY: CGFloat = 0

    var body: some View {
        let list = model.playlist
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text("Liste de lecture").font(.title2).fontWeight(.semibold)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("Répéter").foregroundStyle(.secondary)
                        RepeatPicker()
                    }
                    .disabled(model.player.mode == .followTransport)
                }
                lead
                if list.playlist.isEmpty {
                    empty
                } else {
                    table(list)
                    Text("Double-clic pour lire à partir d'un fichier. Glissez les lignes pour changer l'ordre.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
            .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { model.receive($0, append: true) }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { removeSelected() }
    }

    @ViewBuilder private var lead: some View {
        if model.player.mode == .followTransport {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text("Avec le transport JACK, la liste ne se lit pas toute seule : le transport décide. Un double-clic ouvre un fichier, qui se lit alors avec le transport.")
            }
            .font(.callout).foregroundStyle(.secondary)
        } else {
            Text("Les fichiers se lisent l'un après l'autre, sans coupure. Chacun garde ses propres branchements.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func removeSelected() {
        guard let s = selected else { return }
        model.playlist.remove(at: [s])
        selected = nil
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("La liste est vide").font(.title3).fontWeight(.medium)
            Text("Déposez des fichiers ici, ou choisissez-les.").font(.callout).foregroundStyle(.secondary)
            Button("Ajouter des fichiers…") { model.addFiles() }.buttonStyle(.borderedProminent).controlSize(.large).accentTint().padding(.top, 6)
            Button("Ouvrir une liste…") { model.openPlaylistFile() }.buttonStyle(.link)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }

    // MARK: The table

    private func table(_ list: PlaylistModel) -> some View {
        let items = list.playlist.items
        return VStack(spacing: 0) {
            PlaylistColumns.header
            let target = dragged.map { Self.target(from: $0, moved: dragY, count: items.count) }
            ForEach(Array(items.enumerated()), id: \.offset) { index, url in
                PlaylistRow(index: index, url: url, isSelected: selected == index, isLast: index == items.count - 1,
                            isDragged: dragged == index, offset: Self.offset(of: index, dragged: dragged, target: target, moved: dragY, count: items.count)) {
                    selected = index
                } play: {
                    selected = index
                    list.select(index, play: model.player.mode == .independent)
                } dragChanged: { y in
                    if dragged != index { dragged = index; selected = index }
                    dragY = y
                } dragEnded: {
                    if let from = dragged {
                        let to = Self.target(from: from, moved: dragY, count: items.count)
                        withAnimation(.snappy(duration: 0.15)) {
                            if to != from { list.move(from: [from], to: to > from ? to + 1 : to); selected = to }
                            dragged = nil
                            dragY = 0
                        }
                    }
                }
                .zIndex(dragged == index ? 1 : 0)
            }
            // The bar under the list, as in the lists of macOS: add on the left, the rest in a menu on the right.
            HStack(spacing: 10) {
                Menu {
                    Button("Ajouter des fichiers…") { model.addFiles() }
                    Button("Ouvrir une liste…") { model.openPlaylistFile() }
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Ajouter à la liste")
                Text(Plural.files(items.count)).foregroundStyle(.secondary)
                Spacer()
                Text("Durée totale \(TimeFormat.clock(items.reduce(0) { $0 + (model.info(of: $1)?.duration ?? 0) }))").foregroundStyle(.secondary)
                Menu {
                    Button("Enregistrer la liste…") { model.savePlaylist() }
                    Divider()
                    Button("Vider la liste", role: .destructive) { list.replace(with: []); selected = nil }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Plus d'actions")
            }
            .font(.caption).padding(.horizontal, 12).frame(height: 34)
            .overlay(alignment: .top) { Divider() }
        }
        .blockBackground()
    }
}

extension PlaylistView {
    /// The place the dragged row would take if it were dropped now.
    static func target(from: Int, moved: CGFloat, count: Int) -> Int {
        min(max(from + Int((moved / PlaylistColumns.rowHeight).rounded()), 0), max(count - 1, 0))
    }

    /// How far a row is from its place while one is dragged: the dragged one follows the pointer, the ones it passes make room.
    static func offset(of index: Int, dragged: Int?, target: Int?, moved: CGFloat, count: Int) -> CGFloat {
        guard let dragged, let target else { return 0 }
        if index == dragged {
            return min(max(moved, -CGFloat(dragged) * PlaylistColumns.rowHeight), CGFloat(count - 1 - dragged) * PlaylistColumns.rowHeight)
        }
        if dragged < index, index <= target { return -PlaylistColumns.rowHeight }
        if target <= index, index < dragged { return PlaylistColumns.rowHeight }
        return 0
    }
}

/// The widths of the columns, shared by the header and the rows.
private enum PlaylistColumns {
    static let grip: CGFloat = 14, place: CGFloat = 22, channels: CGFloat = 62, rate: CGFloat = 76, duration: CGFloat = 60, trash: CGFloat = 24, rowHeight: CGFloat = 52

    static var header: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: grip)
            Text("N°").frame(width: place)
            Text("Nom").frame(maxWidth: .infinity, alignment: .leading)
            Text("Voies").frame(width: channels, alignment: .trailing)
            Text("Fréquence").frame(width: rate, alignment: .trailing)
            Text("Durée").frame(width: duration, alignment: .trailing)
            Color.clear.frame(width: trash)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 30)
        .background(Color.primary.opacity(0.05))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One file of the list.
private struct PlaylistRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    let index: Int
    let url: URL
    let isSelected: Bool
    let isLast: Bool
    let isDragged: Bool
    let offset: CGFloat
    let select: () -> Void
    let play: () -> Void
    let dragChanged: (CGFloat) -> Void
    let dragEnded: () -> Void
    @State private var isHovered = false

    var body: some View {
        let list = model.playlist
        let current = list.playlist.current == index
        let info = model.info(of: url)
        let serverRate = model.graph.sampleRate.map(Double.init)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: PlaylistColumns.grip)
            status(current).frame(width: PlaylistColumns.place)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: url.lastPathComponent).fontWeight(.medium).foregroundStyle(current ? accent : Color.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: info.map { "\($0.container) · \($0.encoding) · " + url.deletingLastPathComponent().lastPathComponent } ?? url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let info {
                let differs = serverRate.map { abs($0 - info.sampleRate) > 0.5 } ?? false
                Text(verbatim: "\(info.channels)").frame(width: PlaylistColumns.channels, alignment: .trailing)
                Text(verbatim: (info.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz")
                    .foregroundStyle(differs ? Color.orange : Color.primary).frame(width: PlaylistColumns.rate, alignment: .trailing)
                    .help(differs ? Text("La fréquence du fichier diffère de celle de JACK : il est rééchantillonné.") : Text(verbatim: ""))
                Text(verbatim: TimeFormat.clock(info.duration)).frame(width: PlaylistColumns.duration, alignment: .trailing)
            } else {
                Chip(text: Text("Introuvable"), kind: .warn, symbol: "exclamationmark.triangle.fill")
            }
            Button { model.playlist.remove(at: [index]) } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .frame(width: PlaylistColumns.trash, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Retirer de la liste")
        }
        .font(.callout).monospacedDigit()
        .onHover { isHovered = $0 }
        .padding(.horizontal, 14).frame(height: PlaylistColumns.rowHeight)
        .background { if isDragged { Rectangle().fill(.regularMaterial).shadow(radius: 6) } else { Color.clear } }
        .background(isSelected ? accent.opacity(0.13) : Color.clear)
        .overlay(alignment: .bottom) { if !isLast, !isDragged { Divider().padding(.leading, 14) } }
        .overlay(alignment: .bottomLeading) {
            if current, model.player.file != nil {
                GeometryReader { geo in Rectangle().fill(accent).frame(width: geo.size.width * model.player.fraction, height: 2) }.frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: play)
        .onTapGesture(perform: select)
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { dragChanged($0.translation.height) }
            .onEnded { _ in dragEnded() })
        .offset(y: offset)
        .animation(isDragged ? nil : .snappy(duration: 0.15), value: offset)
    }

    /// The place of the file, or what it does if it is the one that plays.
    @ViewBuilder private func status(_ current: Bool) -> some View {
        if current {
            Image(systemName: model.player.isPlaying ? "speaker.wave.2.fill" : "pause.fill").font(.system(size: 12)).foregroundStyle(accent)
        } else {
            Text(verbatim: "\(index + 1)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// None, the file, or the whole list: three segments, as in the design.
struct RepeatPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            segment("Aucune", .off)
            segment("Fichier", .file)
            segment("Liste", .list)
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func segment(_ title: LocalizedStringKey, _ mode: RepeatMode) -> some View {
        let on = model.playlist.repeatMode == mode
        return Button { model.set(repeatMode: mode) } label: {
            Text(title).fontWeight(on ? .medium : .regular)
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 14).frame(height: 24)
                .background { if on { Capsule().fill(accent) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
