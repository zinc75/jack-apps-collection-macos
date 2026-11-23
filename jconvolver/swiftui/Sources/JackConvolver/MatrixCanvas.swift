// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import SwiftUI

/// The matrix: the inputs in rows, the outputs in columns, a cell for each pair, lit when an impulse response is placed on it.
struct MatrixCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @State private var dragStart: ConvPair?
    @State private var viewportSize = CGSize.zero
    @State private var zoomOrigin: CGFloat?
    @State private var wheel = WheelMonitor()

    private let labelWidth: CGFloat = 76

    private var topMargin: CGFloat { model.cellSize >= 18 ? 64 : 22 }

    var body: some View {
        let document = model.document
        let n = document?.inputCount ?? 0, m = document?.outputCount ?? 0, cs = model.cellSize
        let size = CGSize(width: labelWidth + CGFloat(m) * cs + 2, height: topMargin + CGFloat(n) * cs + 2)
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                // At the top left of the frame when it is bigger than the matrix, not in the middle.
                Canvas { context, _ in draw(context, n: n, m: m, cs: cs) }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(selectGesture(n: n, m: m, cs: cs))
                    .onContinuousHover { phase in
                        if case .active(let point) = phase {
                            model.hoverPair = pair(at: point, n: n, m: m, cs: cs)
                            model.hoverPoint = point
                        } else {
                            model.hoverPair = nil
                            model.hoverPoint = nil
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("matrixPage")) } action: { model.matrixContentFrame = $0 }
                    .onChange(of: model.dragPointer) { _, pointer in updateDrop(pointer, n: n, m: m, cs: cs) }
                    .focusable()
                    .focusEffectDisabled()
                    .onDeleteCommand { model.clearSelection() }
                    .contextMenu { contextMenu }
                    .onAppear { RightClickSelector.install(model) }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("matrixPage")) } action: { model.matrixViewport = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0; applyFit() }
        .onChange(of: n) { applyFit() }
        .onChange(of: m) { applyFit() }
        .onAppear { wheel.start(model) }
        // The whole block zooms, not only the cells: pinch, and command with the wheel while the pointer is anywhere in it.
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                let origin = zoomOrigin ?? model.cellSize
                zoomOrigin = origin
                model.zoom(by: origin * value.magnification / max(model.cellSize, 1))
            }
            .onEnded { _ in zoomOrigin = nil; model.endZoom() })
        .onContinuousHover { phase in
            if case .active = phase { model.pointerInMatrixBlock = true } else { model.pointerInMatrixBlock = false }
        }
        .blockBackground()
        .overlay(alignment: .topLeading) { HoverCardLayer() }
        .overlay { EmptyMatrixHint() }
        .overlay(alignment: .bottomTrailing) { ResetZoomButton() }
        .overlay(alignment: .topTrailing) { GesturesButton() }
    }

    // MARK: The size of the cells

    /// The size of a cell with which the matrix fills the block, as far as it goes: the whole matrix is seen, without scrolling.
    private func fitSize(n: Int, m: Int) -> CGFloat {
        guard n > 0, m > 0, viewportSize.width > 0, viewportSize.height > 0 else { return 26 }
        func size(top: CGFloat) -> CGFloat {
            min((viewportSize.width - labelWidth - 3) / CGFloat(m), (viewportSize.height - top - 3) / CGFloat(n))
        }
        let big = size(top: 64)
        let cs = big >= 18 ? big : size(top: 22)
        return min(max(cs.rounded(.down), 6), 64)
    }

    private func applyFit() {
        let n = model.document?.inputCount ?? 0, m = model.document?.outputCount ?? 0
        let fit = fitSize(n: n, m: m)
        model.fitCellSize = fit
        if !model.zoomIsManual { model.cellSize = fit }
    }

    /// While something is dragged from the list: where it would land.
    private func updateDrop(_ pointer: CGPoint?, n: Int, m: Int, cs: CGFloat) {
        model.dropBlocked = false
        model.dropOnPanel = false
        guard let pointer, !model.draggedItems.isEmpty else { model.dropPlan = nil; return }
        let flags = NSEvent.modifierFlags
        let mode: PlacementMode = flags.contains(.option) ? .column : flags.contains(.shift) ? .diagonal : .row
        // Above the panel under the matrix: it goes to the chosen cells.
        if model.selectionPanelFrame.contains(pointer), !model.matrixViewport.contains(pointer) {
            model.dropOnPanel = true
            model.dropPlan = model.panelDropPlan(mode: mode)
            return
        }
        guard model.matrixViewport.contains(pointer) else { model.dropPlan = nil; return }
        let local = CGPoint(x: pointer.x - model.matrixContentFrame.minX, y: pointer.y - model.matrixContentFrame.minY)
        guard let pair = pair(at: local, n: n, m: m, cs: cs) else { model.dropPlan = nil; return }
        // Dropped on one of several chosen cells: one thing goes on all of them; several things cannot be dropped there.
        model.dropBlocked = false
        if model.selection.pairs.count > 1, model.selection.contains(pair) {
            if model.draggedItems.count == 1 {
                model.dropPlan = Placement.distribute(model.draggedItems, over: model.selection.pairs)
            } else {
                model.dropPlan = nil
                model.dropBlocked = true
            }
        } else {
            model.dropPlan = model.plan(model.draggedItems, from: pair, mode: mode)
        }
    }

    // MARK: The menu of a right-click

    /// The impulse responses read from a file on the cell under the pointer, with their place on the cell.
    private var inspectable: [(index: Int, impulse: ConvImpulse)] {
        guard let pair = model.hoverPair, let document = model.document else { return [] }
        return document.impulses(at: pair).enumerated().compactMap { index, impulse in
            if case .file = impulse.source { (index, impulse) } else { nil }
        }
    }

    /// Opens the page of an impulse response of the cell: one entry when there is one, a list when there are several.
    @ViewBuilder
    private var inspectItems: some View {
        let items = inspectable
        if items.count > 1 {
            Menu("Inspecter les réponses impulsionnelles") {
                ForEach(items, id: \.index) { item in
                    Button(model.label(of: item.impulse)) { inspect(item.index) }
                }
            }
            if !model.traces.isEmpty {
                Menu("Ajouter aux tracés") {
                    ForEach(items, id: \.index) { item in
                        Button(model.label(of: item.impulse)) { inspect(item.index, adding: true) }
                    }
                }
            }
        } else {
            Button("Inspecter la réponse impulsionnelle…") { if let item = items.first { inspect(item.index) } }
                .disabled(items.isEmpty)
            if !model.traces.isEmpty, let item = items.first {
                Button("Ajouter au tracé") { inspect(item.index, adding: true) }
            }
        }
    }

    private func inspect(_ index: Int, adding: Bool = false) {
        if let pair = model.hoverPair { model.inspect(DetailTarget(pair: pair, index: index), adding: adding) }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copier") { model.copySelection() }.disabled(!model.canCopy)
        Button("Couper") { model.cutSelection() }.disabled(!model.canCopy)
        Button("Coller") { model.paste() }.disabled(model.clipboard.isEmpty)
        Button("Vider", role: .destructive) { model.clearSelection() }.disabled(!model.canCopy)
        inspectItems
        Divider()
        if model.placesOnAllChosenCells {
            Button("Placer sur toutes les cases choisies") { model.placePicked(mode: .row) }
                .disabled(!model.canPlaceOnChosenCells)
        } else {
            Menu("Placer ici ce qui est choisi dans la liste") {
                Button("En ligne") { model.placePicked(mode: .row) }
                Button("En colonne") { model.placePicked(mode: .column) }
                Button("En diagonale") { model.placePicked(mode: .diagonal) }
            }
            .disabled(model.picked.isEmpty)
        }
        Divider()
        Button("Sélectionner toute la ligne") {
            if let p = model.hoverPair ?? Optional(ConvPair(input: model.selection.bounds.firstInput, output: 0)), let d = model.document {
                model.selection.selectInput(p.input, outputs: d.outputCount)
            }
        }
        Button("Sélectionner toute la colonne") {
            if let p = model.hoverPair ?? Optional(ConvPair(input: 0, output: model.selection.bounds.firstOutput)), let d = model.document {
                model.selection.selectOutput(p.output, inputs: d.inputCount)
            }
        }
        Button("Sélectionner tout ce qui utilise ce fichier") {
            if let p = model.hoverPair ?? Optional(ConvPair(input: model.selection.bounds.firstInput, output: model.selection.bounds.firstOutput)) { model.selectPairsUsingFile(of: p) }
        }
        .disabled(inspectable.isEmpty)
    }

    // MARK: Where things are

    private struct Hit { var pair: ConvPair?; var inRow: Int?; var inColumn: Int? }

    private func hit(_ point: CGPoint, n: Int, m: Int, cs: CGFloat) -> Hit {
        let o = Int(((point.x - labelWidth) / cs).rounded(.down)), i = Int(((point.y - topMargin) / cs).rounded(.down))
        if point.x < labelWidth, i >= 0, i < n { return Hit(inRow: i) }
        if point.y < topMargin, o >= 0, o < m { return Hit(inColumn: o) }
        if o >= 0, o < m, i >= 0, i < n { return Hit(pair: ConvPair(input: i, output: o)) }
        return Hit()
    }

    private func pair(at point: CGPoint, n: Int, m: Int, cs: CGFloat) -> ConvPair? { hit(point, n: n, m: m, cs: cs).pair }

    private func rect(_ pair: ConvPair, cs: CGFloat) -> CGRect {
        CGRect(x: labelWidth + CGFloat(pair.output) * cs, y: topMargin + CGFloat(pair.input) * cs, width: cs, height: cs)
    }

    // MARK: Clicking and dragging

    private func selectGesture(n: Int, m: Int, cs: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let h = hit(value.location, n: n, m: m, cs: cs)
                model.isSelecting = true
                if dragStart == nil {
                    // The start of the gesture: the gutters pick a whole row or column; a cell starts a block, or is added with command
                    // and extends with shift.
                    if let i = h.inRow { model.selection.selectInput(i, outputs: m); dragStart = ConvPair(input: i, output: -1); return }
                    if let o = h.inColumn { model.selection.selectOutput(o, inputs: n); dragStart = ConvPair(input: -1, output: o); return }
                    guard let pair = h.pair else { return }
                    let flags = NSEvent.modifierFlags
                    if flags.contains(.command) { model.selection.toggle(pair); dragStart = pair; return }
                    if flags.contains(.shift) { model.selection.extend(to: pair); dragStart = pair; return }
                    model.selection.select(pair)
                    dragStart = pair
                } else if let start = dragStart, start.input >= 0, start.output >= 0, let pair = h.pair,
                          !NSEvent.modifierFlags.contains(.command), !NSEvent.modifierFlags.contains(.shift) {
                    model.selection.select(from: start, to: pair)
                }
            }
            .onEnded { _ in dragStart = nil; model.isSelecting = false }
            .simultaneously(with: SpatialTapGesture(count: 2).onEnded { value in
                // Double-click on an empty cell: what is chosen in the list goes there.
                guard let pair = pair(at: value.location, n: n, m: m, cs: cs), model.document?.impulses(at: pair).isEmpty == true else { return }
                model.apply(model.plan(model.orderedPicks(), from: pair, mode: .row))
            })
    }

    // MARK: Drawing

    private func draw(_ context: GraphicsContext, n: Int, m: Int, cs: CGFloat) {
        guard let document = model.document, n > 0, m > 0 else { return }
        let hover = model.hoverPair, inError = model.pairsInError
        let labelColor = Color.secondary, strongLabel = Color.primary
        let labelsOnTop = cs >= 18
        let stepI = cs >= 14 ? 1 : cs >= 9 ? 2 : 5, stepO = cs >= 18 ? 1 : cs >= 11 ? 2 : 4
        let font = Font.system(size: 11)

        // Names of the inputs, on the left, and of the outputs, on top (turned, as the matrix of the mockup does).
        for i in 0..<n where i % stepI == 0 {
            let name = fit(model.inputLabel(i), width: labelWidth - 12)
            context.draw(Text(name).font(font).foregroundColor(hover?.input == i ? strongLabel : labelColor),
                         at: CGPoint(x: labelWidth - 6, y: topMargin + CGFloat(i) * cs + cs / 2), anchor: .trailing)
        }
        for o in 0..<m where o % stepO == 0 {
            let x = labelWidth + CGFloat(o) * cs + cs / 2
            if labelsOnTop {
                let name = fit(model.outputLabel(o), width: topMargin - 8)
                context.drawLayer { layer in
                    layer.translateBy(x: x, y: topMargin - 6)
                    layer.rotate(by: .degrees(-90))
                    layer.draw(Text(name).font(font).foregroundColor(hover?.output == o ? strongLabel : labelColor), at: .zero, anchor: .leading)
                }
            } else {
                context.draw(Text("\(o + 1)").font(.system(size: 9)).foregroundColor(labelColor), at: CGPoint(x: x, y: topMargin - 8))
            }
        }

        // The band of the row and of the column under the pointer.
        if let hover {
            let band = Color.gray.opacity(0.14)
            context.fill(Path(CGRect(x: labelWidth, y: topMargin + CGFloat(hover.input) * cs, width: CGFloat(m) * cs, height: cs)), with: .color(band))
            context.fill(Path(CGRect(x: labelWidth + CGFloat(hover.output) * cs, y: topMargin, width: cs, height: CGFloat(n) * cs)), with: .color(band))
        }

        let radius = min(4, cs / 6)
        for i in 0..<n {
            for o in 0..<m {
                let pair = ConvPair(input: i, output: o)
                let cell = rect(pair, cs: cs).insetBy(dx: 1, dy: 1)
                let impulses = document.impulses(at: pair)
                if impulses.isEmpty {
                    context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
                    continue
                }
                drawImpulse(context, impulses, in: cell, radius: radius)
                if inError.contains(pair) {
                    context.stroke(Path(roundedRect: cell.insetBy(dx: 1, dy: 1), cornerRadius: radius), with: .color(.red), lineWidth: 2)
                }
            }
        }

        // A drop that cannot be done: the chosen cells are outlined in red.
        if model.dropBlocked {
            for pair in model.selection.pairs {
                let cell = rect(pair, cs: cs).insetBy(dx: 1, dy: 1)
                context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.red.opacity(0.28)))
                context.stroke(Path(roundedRect: cell.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius), with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }

        // What a drop would place.
        if let plan = model.dropPlan {
            for (order, item) in plan.items.enumerated() {
                let cell = rect(item.pair, cs: cs).insetBy(dx: 1, dy: 1)
                context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(accent.opacity(0.38)))
                context.stroke(Path(roundedRect: cell.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius), with: .color(accent), lineWidth: 1.5)
                // A cell that has something already gets one more impulse response: a plus says so.
                if !(model.document?.impulses(at: item.pair).isEmpty ?? true), cs >= 16 {
                    context.draw(Text(verbatim: "+").font(.system(size: 13, weight: .heavy)).foregroundColor(.white),
                                 at: CGPoint(x: cell.maxX - 7, y: cell.minY + 8), anchor: .center)
                }
                // The order in which they are placed, when there are several (it shows where a row ends and the next one goes on).
                if plan.items.count > 1, cs >= 16 {
                    context.draw(Text(verbatim: "\(order + 1)").font(.system(size: min(13, cs * 0.5), weight: .semibold)).foregroundColor(.white),
                                 at: CGPoint(x: cell.midX, y: cell.midY), anchor: .center)
                }
            }
        }

        // What was copied stays outlined, dashed, where it came from.
        if let copied = model.clipboardShape {
            let dash = StrokeStyle(lineWidth: 1.5, dash: [5, 3])
            switch copied {
            case .block(let b):
                let frame = CGRect(x: labelWidth + CGFloat(b.firstOutput) * cs, y: topMargin + CGFloat(b.firstInput) * cs,
                                   width: CGFloat(b.lastOutput - b.firstOutput + 1) * cs, height: CGFloat(b.lastInput - b.firstInput + 1) * cs)
                context.stroke(Path(frame.insetBy(dx: 2.5, dy: 2.5)), with: .color(.white.opacity(0.85)), style: dash)
            case .picked(let set):
                for pair in set { context.stroke(Path(rect(pair, cs: cs).insetBy(dx: 2.5, dy: 2.5)), with: .color(.white.opacity(0.85)), style: dash) }
            }
        }

        // The selection: one frame around a block, a frame for each picked pair.
        switch model.selection.shape {
        case .block(let b):
            let frame = CGRect(x: labelWidth + CGFloat(b.firstOutput) * cs, y: topMargin + CGFloat(b.firstInput) * cs,
                               width: CGFloat(b.lastOutput - b.firstOutput + 1) * cs, height: CGFloat(b.lastInput - b.firstInput + 1) * cs)
            context.fill(Path(frame), with: .color(accent.opacity(0.12)))
            context.stroke(Path(frame.insetBy(dx: 1, dy: 1)), with: .color(accent), lineWidth: 2)
        case .picked(let set):
            for pair in set {
                let frame = rect(pair, cs: cs)
                context.fill(Path(frame), with: .color(accent.opacity(0.12)))
                context.stroke(Path(frame.insetBy(dx: 1, dy: 1)), with: .color(accent), lineWidth: 2)
            }
        }
    }

    /// A cell with something on it: the intensity says the gain, the drawing says the kind.
    private func drawImpulse(_ context: GraphicsContext, _ impulses: [ConvImpulse], in cell: CGRect, radius: CGFloat) {
        let first = impulses[0]
        let db = first.gainDB
        let intensity = db.isFinite ? min(1, max(0.22, 0.22 + 0.78 * (db + 36) / 36)) : 0.22
        let color = accent.opacity(intensity)
        switch first.source {
        case .file:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(color))
            // A decorative impulse response, the symbol of the system the detail button uses too (the same on every cell: it says what the cell
            // holds, not what the file is), when the cell is large enough for it not to be noise.
            if cell.width >= 20 {
                let ink = context.environment.colorScheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.30)
                let glyph = context.resolve(Text(Image(systemName: "waveform.path.ecg")).font(.system(size: cell.width * 0.5, weight: .regular)).foregroundColor(ink))
                context.draw(glyph, at: CGPoint(x: cell.midX, y: cell.midY), anchor: .center)
            }
        case .dirac:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
            if cell.width >= 13 {
                // The pulse is a delta.
                context.draw(Text(verbatim: "δ").font(.system(size: cell.width * 0.62, weight: .semibold, design: .serif)).italic().foregroundColor(accent),
                             at: CGPoint(x: cell.midX, y: cell.midY), anchor: .center)
            } else {
                context.fill(Path(CGRect(x: cell.midX - 1, y: cell.minY + 3, width: 2, height: cell.height - 6)), with: .color(accent))
            }
        case .hilbert where cell.width >= 13:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
            // The Hilbert transform is an H, as in the books.
            context.draw(Text(verbatim: "H").font(.system(size: cell.width * 0.6, weight: .semibold, design: .serif)).italic().foregroundColor(accent),
                         at: CGPoint(x: cell.midX, y: cell.midY), anchor: .center)
        case .hilbert:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
            context.drawLayer { layer in
                layer.clip(to: Path(roundedRect: cell, cornerRadius: radius))
                var hatch = Path()
                var x = cell.minX - cell.height
                while x < cell.maxX {
                    hatch.move(to: CGPoint(x: x, y: cell.maxY)); hatch.addLine(to: CGPoint(x: x + cell.height, y: cell.minY))
                    x += 4
                }
                layer.stroke(hatch, with: .color(accent), lineWidth: 1.4)
            }
        case .copy:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
            context.stroke(Path(roundedRect: cell.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius), with: .color(accent),
                           style: StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
        }
        // More than one impulse response on the cell: a counter, as on the badge of an application, kept inside the cell (a small dark
        // disc with white figures, which reads on every shade of the cell).
        if impulses.count > 1, cell.width >= 13 {
            let d = min(max(cell.width * 0.4, 11), 15)
            let text = impulses.count > 9 ? "9+" : "\(impulses.count)"
            let width = text.count > 1 ? d * 1.35 : d
            let badge = CGRect(x: cell.maxX - width - 2.5, y: cell.minY + 2.5, width: width, height: d)
            let shape = Path(roundedRect: badge, cornerRadius: d / 2)
            context.fill(shape, with: .color(Color.black.opacity(0.62)))
            context.stroke(shape, with: .color(Color.white.opacity(0.35)), lineWidth: 0.75)
            context.draw(Text(verbatim: text).font(.system(size: d * 0.66, weight: .bold)).foregroundColor(.white),
                         at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
        } else if impulses.count > 1 {
            context.fill(Path(ellipseIn: CGRect(x: cell.maxX - 6, y: cell.minY + 1, width: 5, height: 5)), with: .color(.white.opacity(0.9)))
        }
    }

    /// A name that fits in a width, with an ellipsis (about 6 points a character at this size).
    private func fit(_ text: String, width: CGFloat) -> String {
        let room = max(3, Int(width / 6))
        return text.count <= room ? text : String(text.prefix(room - 1)) + "…"
    }
}

/// Command and the scroll wheel (or two fingers on the trackpad) zoom the matrix while the pointer is above it.
final class WheelMonitor {
    private var token: Any?
    func start(_ model: AppModel) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak model] event in
            guard let model, event.modifierFlags.contains(.command), model.pointerInMatrixBlock else { return event }
            let step = event.hasPreciseScrollingDeltas ? 0.012 : 0.06
            model.zoom(by: exp(event.scrollingDeltaY * step))
            if event.phase.contains(.ended) || event.momentumPhase.contains(.ended) { model.endZoom() }
            return nil
        }
    }
    deinit { if let token { NSEvent.removeMonitor(token) } }
}
