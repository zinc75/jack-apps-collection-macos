// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import PlotKit
import SwiftUI

/// What the page of the analysis says of one trace: where it is in the matrix, what tells it apart, and a remark when it has another sample rate
/// than the edited one.
struct TraceRow: Identifiable {
    /// The number of the trace from 0, which is the number of its channel in the series of the plots.
    let id: Int
    let target: DetailTarget
    let name: String
    let detail: String
    let note: String?
}

/// A choice to make when the person asks for a response while others are drawn: a small block, not modal, at the button they used.
struct InspectChoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: DetailTarget
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Des réponses sont déjà tracées.").font(.headline)
            HStack(spacing: 8) {
                Button("Ajouter aux tracés") { choose(.add) }.buttonStyle(.borderedProminent).accentTint()
                Button("Tracer seule") { choose(.replace) }
            }
            Toggle("Mémoriser mon choix", isOn: $remember).toggleStyle(.checkbox).font(.callout).accentTint()
        }
        .padding(14)
    }

    private func choose(_ choice: InspectChoice) {
        if remember { model.inspectChoice = choice }
        model.inspect(target, adding: choice == .add)
        dismiss()
    }
}

/// A symbol of the size the buttons of the footer of the list of files have.
struct TraceGlyph: View {
    let name: String
    var body: some View { Image(systemName: name).resizable().scaledToFit().frame(width: 16, height: 16) }
}

/// The colour of a trace: a round swatch that opens a row of round swatches, as the accent is chosen in the settings of the application.
struct TraceColorButton: View {
    @Binding var color: Color
    @Environment(\.appAccentColor) private var accent
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Circle().fill(color).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.75))
                .padding(3)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Couleur de la trace"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { i in
                    let swatch = PlotSeriesSet.defaultColor(i, accent: accent)
                    Button { color = swatch; open = false } label: {
                        swatch.frame(width: 20, height: 20).clipShape(Circle()).padding(3)
                            .overlay(Circle().strokeBorder(swatch == color ? Color.primary.opacity(0.7) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }
}

/// The responses of the matrix that can be added to the traces: the ones of the selection first, then all of them.
struct AddTraceMenu<Label: View>: View {
    @Environment(AppModel.self) private var model
    let label: Label

    init(@ViewBuilder label: () -> Label) { self.label = label() }

    private func title(_ target: DetailTarget) -> String { model.traceFullName(target) + " · " + model.traceDetail(target) }

    var body: some View {
        let selected = model.traceCandidates(in: model.selection.pairs)
        let all = model.traceCandidates()
        Menu {
            Button(String(localized: "Toutes les RI de la configuration") + " (\(all.count))") { model.addTraces(all) }.disabled(all.isEmpty)
            Divider()
            if !selected.isEmpty {
                Section("Dans la sélection") {
                    ForEach(selected.prefix(40)) { target in Button(title(target)) { model.inspect(target, adding: true) } }
                }
            }
            if all.count > selected.count {
                Menu("Toute la matrice") {
                    ForEach(all.prefix(80)) { target in Button(title(target)) { model.inspect(target, adding: true) } }
                }
            }
        } label: { label }
        .menuStyle(.button).menuIndicator(.hidden).fixedSize()
        .disabled(all.isEmpty)
    }
}

/// The page "Tracés" of the inspector: the responses that are drawn, which of them is edited, their colour, and how an inspect button behaves.
struct TracesInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Bindable var series: PlotSeriesSet
    let rows: [TraceRow]
    @Binding var engineView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlotInspectorSection(id: "engineView", title: String(localized: "Signal tracé"),
                                 info: String(localized: "Appliquer troncature, gain et retard : chaque trace est la partie du fichier que jconvolver lit (début et longueur du fichier .conf), multipliée par son gain, après son retard. La forme d'onde, le spectre et la phase sont ceux de la réponse en service. Les poignées de troncature et les repères du fichier sont masqués dans cette vue ; la page Troncature de l'inspecteur reste active.")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Appliquer troncature, gain et retard", isOn: $engineView).toggleStyle(.checkbox).accentTint().font(.callout)
                    if engineView {
                        Text("Poignées et repères du fichier masqués.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            PlotInspectorSection(id: "traces", title: String(localized: "Réponses tracées"),
                                 info: String(localized: "Une trace est un emplacement de la matrice : un même fichier placé deux fois, avec d'autres réglages, donne deux traces. Une seule est éditée à la fois : ses poignées, sa troncature et ses repères sont ceux qu'on voit et qu'on change. Les autres sont tracées plus pâles.")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows) { row in line(row) }
                    // As under the list of files: a discreet "+" and "−", the "−" taking away the trace that is edited.
                    HStack(spacing: 4) {
                        AddTraceMenu { TraceGlyph(name: "plus.circle") }
                            .buttonStyle(GlyphButtonStyle())
                            .help(String(localized: "Ajouter une réponse impulsionnelle aux tracés"))
                        Button { if let edited = model.detail { model.removeTrace(edited) } } label: { TraceGlyph(name: "minus.circle") }
                            .buttonStyle(GlyphButtonStyle())
                            .disabled(model.detail == nil)
                            .help(String(localized: "Ne plus tracer la trace éditée"))
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            PlotInspectorSection(id: "inspectChoice", title: String(localized: "Quand j'inspecte une réponse")) {
                Picker("", selection: Binding(get: { model.inspectChoice }, set: { model.inspectChoice = $0 })) {
                    Text("Demander").tag(InspectChoice.ask)
                    Text("Ajouter aux tracés").tag(InspectChoice.add)
                    Text("Tracer seule").tag(InspectChoice.replace)
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func line(_ row: TraceRow) -> some View {
        let edited = model.detail == row.target
        if series.items.indices.contains(row.id) {
            HStack(alignment: .top, spacing: 6) {
                Toggle("", isOn: $series.items[row.id].isVisible).labelsHidden().toggleStyle(.checkbox).tint(series.items[row.id].color)
                TraceColorButton(color: $series.items[row.id].color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name).font(.callout.weight(edited ? .semibold : .regular)).lineLimit(1)
                    Text(verbatim: row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let note = row.note { Text(verbatim: note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(series.items[row.id].isVisible ? 1 : 0.5)
                Button { model.detail = row.target } label: {
                    Image(systemName: edited ? "pencil.circle.fill" : "pencil.circle")
                        .foregroundStyle(edited ? accent : Color.secondary)
                }
                .buttonStyle(.plain).disabled(!series.items[row.id].isVisible)
                .help(edited ? String(localized: "Trace éditée") : String(localized: "Éditer cette trace"))
            }
            .padding(.vertical, 3)
            .contextMenu {
                Button("Éditer cette trace") { model.detail = row.target }.disabled(edited || !series.items[row.id].isVisible)
                Button("Afficher seule") { series.solo(row.id) }
                Button("Ne plus tracer", role: .destructive) { model.removeTrace(row.target) }
            }
        }
    }
}

/// What the page shows when nothing is drawn: a welcome with two cards. One response: the card turns into the list of those that can be drawn, to
/// choose from. All the responses of the configuration: they are drawn together at once.
struct TracesEmptyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @State private var choosing = false
    /// The three filters of the list: the number of the input, the number of the output (a number, several separated by commas, or a range such as 2-4)
    /// and a part of the name of the file.
    @State private var filterInput = ""
    @State private var filterOutput = ""
    @State private var filterFile = ""
    @State private var hoveredCard: Int?

    var body: some View {
        let all = model.traceCandidates()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Analyse").font(.title2).fontWeight(.semibold)
                Text("Tracez la forme d'onde, le spectre et la phase des réponses impulsionnelles : une seule, ou plusieurs ensemble pour les comparer.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if all.isEmpty {
                Text("Aucune réponse impulsionnelle issue d'un fichier. Placez des fichiers sur les cases de la matrice : elles pourront être tracées ici.")
                    .foregroundStyle(.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(interactive: false)
            } else {
                // Choosing, the list takes the height of the page (and most of its width); the other card stays as it is, at the top.
                HStack(alignment: .top, spacing: 14) {
                    oneCard(all)
                    allCard(all).frame(maxWidth: choosing ? 260 : .infinity)
                }
                .frame(maxHeight: choosing ? .infinity : nil, alignment: .top)
            }
            if !choosing || all.isEmpty { Spacer(minLength: 0) }
        }
        // The width of the home page (760 points of content), so that the cards are as wide as the tiles there.
        .padding(24)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: The cards

    private func tile(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent).frame(width: 38, height: 38)
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
        }
    }

    /// The left card: one response. Its picture and its title stay; a click opens the list to choose from under them, in the same card (a click on
    /// them closes it).
    private func oneCard(_ all: [DetailTarget]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { choosing.toggle(); if !choosing { filterInput = ""; filterOutput = ""; filterFile = "" } } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        tile("waveform.path")
                        Spacer()
                        if choosing { Image(systemName: "chevron.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                    Text("Une réponse impulsionnelle").font(.title3).fontWeight(.semibold)
                    Text("Choisissez celle à tracer parmi les \(all.count) de la configuration, puis ajoutez-en d'autres au besoin.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if choosing { chooser(all) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: choosing ? .infinity : 170, alignment: .topLeading)
        .glassCard(interactive: !choosing, hovered: hoveredCard == 0 && !choosing, selected: choosing)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hoveredCard = $0 ? 0 : (hoveredCard == 0 ? nil : hoveredCard) }
    }

    /// Under the title of the card: the filter, and the responses that can be drawn.
    private func chooser(_ all: [DetailTarget]) -> some View {
        let shown = matches(all)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Entrée", text: $filterInput).textFieldStyle(.roundedBorder).frame(width: 84)
                    .help("Numéro de l'entrée : 3, ou 1,3, ou 2-4")
                TextField("Sortie", text: $filterOutput).textFieldStyle(.roundedBorder).frame(width: 84)
                    .help("Numéro de la sortie : 3, ou 1,3, ou 2-4")
                TextField("Nom du fichier", text: $filterFile).textFieldStyle(.roundedBorder)
                Text("\(shown.count) / \(all.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown.prefix(200)) { target in
                        Button { model.inspect(target) } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: model.traceName(target)).font(.callout.weight(.semibold)).monospacedDigit().frame(width: 64, alignment: .leading)
                                Text(verbatim: model.traceDetail(target)).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5).padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    if shown.count > 200 {
                        Text("… et \(shown.count - 200) de plus : affinez le filtre.").font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }

    /// The right card: all the responses of the configuration, together.
    private func allCard(_ all: [DetailTarget]) -> some View {
        Button { model.addTraces(all) } label: {
            VStack(alignment: .leading, spacing: 10) {
                tile("square.stack.3d.up")
                Text("Toutes les réponses de la configuration").font(.title3).fontWeight(.semibold)
                Text(all.count == 1 ? "La réponse issue d'un fichier est tracée." : "Les \(all.count) réponses issues d'un fichier sont tracées ensemble, pour les comparer.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if all.count > 40 {
                    Label("Beaucoup de réponses : le calcul peut prendre un moment.", systemImage: "clock").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170, alignment: .topLeading)
            .glassCard(hovered: hoveredCard == 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredCard = $0 ? 1 : (hoveredCard == 1 ? nil : hoveredCard) }
    }

    /// The responses that the three filters keep. An empty filter keeps everything.
    private func matches(_ all: [DetailTarget]) -> [DetailTarget] {
        let inputs = NumberFilter.numbers(filterInput), outputs = NumberFilter.numbers(filterOutput)
        let words = filterFile.lowercased().split(separator: " ").map(String.init)
        return all.filter { target in
            if let inputs, !inputs.contains(target.pair.input + 1) { return false }
            if let outputs, !outputs.contains(target.pair.output + 1) { return false }
            guard !words.isEmpty else { return true }
            let file = model.traceDetail(target).lowercased()
            return words.allSatisfy { file.contains($0) }
        }
    }
}

/// A hint of what is drawn, over the plot, when there are several traces: a chip each, in its colour, that is the legend of the plot without the
/// inspector. A click on a chip shows or hides its trace, a double click shows it alone (and again, all of them); the pencil edits it. The
/// one that is edited is stronger.
struct TracesLegend: View {
    @Environment(AppModel.self) private var model
    @Bindable var series: PlotSeriesSet

    /// The height of all the chips, so that the legend takes what it needs.
    @State private var contentHeight: CGFloat = 24
    @State private var scrolled = ScrollEdges()

    private static let chipHeight: CGFloat = 24
    private static let rowGap: CGFloat = 6
    /// Three full rows of chips: what the legend shows at most; beyond that it scrolls, and a part of the next row is left in sight to say so.
    private static let threeRows = 3 * chipHeight + 2 * rowGap + 2
    private static let peek: CGFloat = 16

    private struct ScrollEdges: Equatable { var above = false; var below = false }

    var body: some View {
        let scrolls = contentHeight > Self.threeRows + 1
        ScrollView(.vertical) {
            // The chips go on rows, filled from the right, as many as the width takes: a few traces make one row, many make several.
            FlowLayout(spacing: 6, rowSpacing: Self.rowGap, alignment: 1) {
                ForEach($series.items) { $item in chip($item) }
            }
            .padding(.vertical, 1)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
            ScrollEdges(above: geometry.contentOffset.y > 1,
                        below: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1)
        } action: { _, new in scrolled = new }
        .frame(height: scrolls ? Self.threeRows + Self.peek : max(contentHeight, Self.chipHeight))
        // The row that is cut at the edge fades: there is more that way.
        .mask(LinearGradient(stops: [
            .init(color: scrolled.above ? .clear : .black, location: 0),
            .init(color: .black, location: scrolled.above ? 0.16 : 0),
            .init(color: .black, location: scrolled.below ? 0.82 : 1),
            .init(color: scrolled.below ? .clear : .black, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }

    private func chip(_ item: Binding<PlotSeries>) -> some View {
        let value = item.wrappedValue
        let target = model.traces.indices.contains(value.id) ? model.traces[value.id] : nil
        let edited = target != nil && target == model.detail
        return HStack(spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(value.isVisible ? value.color : Color.clear)
                    .overlay(Circle().strokeBorder(value.color, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                Text(verbatim: value.name).font(.callout.weight(edited ? .semibold : .regular)).lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { series.solo(value.id) }
            .onTapGesture { item.isVisible.wrappedValue.toggle() }
            .help(String(localized: "Clic : afficher ou masquer. Double clic : afficher seule, puis tout réafficher."))
            Button { if let target { model.detail = target } } label: {
                Image(systemName: edited ? "pencil.circle.fill" : "pencil.circle").font(.system(size: 12))
                    .foregroundStyle(edited ? Color.primary : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            // A trace that is not shown cannot be edited.
            .disabled(!value.isVisible)
            .help(edited ? String(localized: "Trace éditée") : String(localized: "Éditer cette trace"))
        }
        .padding(.leading, 9).padding(.trailing, 6)
        .frame(height: Self.chipHeight)
        .background(value.color.opacity(edited ? 0.2 : 0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(value.color.opacity(edited ? 0.7 : 0.3), lineWidth: 1))
        .opacity(value.isVisible ? 1 : 0.5)
    }
}

/// Views one after the other on rows, breaking where the width ends; each row is centred, or pushed to one edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6
    /// Where a row sits in the width: 0 at the leading edge, 0.5 in the middle, 1 at the trailing edge, from which it is filled.
    var alignment: CGFloat = 0.5

    private struct Row { var items: [(index: Int, size: CGSize)] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = (rows[rows.count - 1].items.isEmpty ? 0 : spacing) + size.width
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            let last = rows.count - 1
            rows[last].width += (rows[last].items.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].items.append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let all = rows(for: width, subviews)
        let height = all.map(\.height).reduce(0, +) + CGFloat(max(all.count - 1, 0)) * rowSpacing
        return CGSize(width: proposal.width ?? (all.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: bounds.width, subviews) {
            var x = bounds.minX + (bounds.width - row.width) * alignment
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}
