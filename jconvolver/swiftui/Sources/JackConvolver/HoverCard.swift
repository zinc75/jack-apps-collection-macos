// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import SwiftUI

/// The card that follows the pointer above a cell of the matrix: what is on the cell, at once and without getting in the way (it takes
/// no click). It goes to the other side of the pointer when it would leave the matrix.
struct HoverCardLayer: View {
    @Environment(AppModel.self) private var model
    @State private var monitor = KeyMonitor()
    private let width: CGFloat = 270

    var body: some View {
        if model.showsHoverCard, !model.isSelecting, !model.selectionKeyDown, let pair = model.hoverPair, let point = model.hoverPoint, model.dragPointer == nil, model.document != nil {
            let viewport = model.matrixViewport, content = model.matrixContentFrame
            // The pointer, in the coordinates of the block that holds the matrix.
            let x = point.x + content.minX - viewport.minX, y = point.y + content.minY - viewport.minY
            let flipX = x + 16 + width > viewport.width, flipY = y + 16 + 130 > viewport.height
            HoverCard(pair: pair)
                .frame(width: width, alignment: .leading)
                .offset(x: flipX ? x - 12 - width : x + 16, y: flipY ? max(y - 16 - 110, 4) : y + 16)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
        Color.clear.frame(width: 0, height: 0).onAppear { monitor.start(model) }
    }
}

/// Watches command and shift: while one of them is down a selection is being made, and the card steps aside.
final class KeyMonitor {
    private var token: Any?
    func start(_ model: AppModel) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak model] event in
            model?.selectionKeyDown = !event.modifierFlags.intersection([.command, .shift]).isEmpty
            return event
        }
    }
    deinit { if let token { NSEvent.removeMonitor(token) } }
}

struct HoverCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    let pair: ConvPair

    var body: some View {
        let impulses = model.document?.impulses(at: pair) ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("\(model.inputLabel(pair.input)) → \(model.outputLabel(pair.output))").font(.callout.weight(.semibold))
            if impulses.isEmpty {
                Text("Case vide").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(Array(impulses.prefix(3).enumerated()), id: \.offset) { _, impulse in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.label(of: impulse)).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: figures(impulse)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if impulses.count > 3 {
                    Text("+ \(impulses.count - 3) autres RI").font(.caption).foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }

    private func figures(_ impulse: ConvImpulse) -> String {
        let gain = impulse.gainDB.isFinite ? impulse.gainDB.formatted(.number.precision(.fractionLength(1))) + " dB" : "−∞ dB"
        var parts = [gain]
        if impulse.delay > 0 { parts.append(String(localized: "retard \(impulse.delay)")) }
        if case .file = impulse.source {
            if impulse.offset > 0 { parts.append(String(localized: "début \(impulse.offset)")) }
            if impulse.length > 0 { parts.append(String(localized: "longueur \(impulse.length)")) }
        }
        return parts.joined(separator: " · ")
    }
}
