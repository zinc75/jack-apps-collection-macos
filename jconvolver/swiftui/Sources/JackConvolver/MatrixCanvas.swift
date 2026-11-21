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
                        if case .active(let point) = phase { model.hoverPair = pair(at: point, n: n, m: m, cs: cs) } else { model.hoverPair = nil }
                    }
                    .onDrop(of: [.plainText], delegate: MatrixDropDelegate(model: model) { point in pair(at: point, n: n, m: m, cs: cs) })
                    .focusable()
                    .focusEffectDisabled()
                    .onDeleteCommand { model.clearSelection() }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .blockBackground()
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
            .onEnded { _ in dragStart = nil }
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

        // What a drop would place.
        if let plan = model.dropPlan {
            for item in plan.items {
                let cell = rect(item.pair, cs: cs).insetBy(dx: 1, dy: 1)
                context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(accent.opacity(0.38)))
                context.stroke(Path(roundedRect: cell.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius), with: .color(accent), lineWidth: 1.5)
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
        case .dirac:
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(Color.primary.opacity(0.07)))
            context.fill(Path(CGRect(x: cell.midX - 1, y: cell.minY + 3, width: 2, height: cell.height - 6)), with: .color(accent))
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
        if impulses.count > 1 {
            context.fill(Path(ellipseIn: CGRect(x: cell.maxX - 6, y: cell.minY + 1, width: 5, height: 5)), with: .color(.white.opacity(0.9)))
        }
    }

    /// A name that fits in a width, with an ellipsis (about 6 points a character at this size).
    private func fit(_ text: String, width: CGFloat) -> String {
        let room = max(3, Int(width / 6))
        return text.count <= room ? text : String(text.prefix(room - 1)) + "…"
    }
}

/// What is dragged over the matrix from the list of files: where it would land is shown, and it is placed when it is dropped.
struct MatrixDropDelegate: DropDelegate {
    let model: AppModel
    let pairAt: (CGPoint) -> ConvPair?

    private var mode: PlacementMode {
        let flags = NSEvent.modifierFlags
        return flags.contains(.option) ? .column : flags.contains(.shift) ? .diagonal : .row
    }

    func validateDrop(info: DropInfo) -> Bool { !model.draggedItems.isEmpty }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let pair = pairAt(info.location) { model.dropPlan = model.plan(model.draggedItems, from: pair, mode: mode) } else { model.dropPlan = nil }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { model.dropPlan = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { model.dropPlan = nil; model.draggedItems = [] }
        guard let pair = pairAt(info.location) else { return false }
        model.apply(model.plan(model.draggedItems, from: pair, mode: mode))
        return true
    }
}
