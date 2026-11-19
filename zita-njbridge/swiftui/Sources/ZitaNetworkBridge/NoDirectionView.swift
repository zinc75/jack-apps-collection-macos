// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// What the pages show when neither Recevoir nor Envoyer is on: a question, and the two answers as large tiles to click (the switches
/// of the footer do the same). `compact` is for the pages of settings, which are not as empty.
struct NoDirectionView: View {
    var compact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        VStack(spacing: compact ? 18 : 28) {
            VStack(spacing: 6) {
                if !compact {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary).padding(.bottom, 6)
                }
                Text("Que voulez-vous faire ?").font(compact ? .title3 : .title2).fontWeight(.semibold)
                Text("Recevoir du son d'un autre Mac, lui en envoyer, ou les deux.").foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ChoiceTile(symbols: [LinkDirection.receive.symbol], title: "Recevoir", detail: "Ce Mac écoute le réseau et reçoit le son d'un autre Mac.") { controller.receiveArmed = true }
                ChoiceTile(symbols: [LinkDirection.send.symbol], title: "Envoyer", detail: "Ce Mac envoie du son vers un autre Mac.") { controller.sendArmed = true }
                ChoiceTile(symbols: ["arrow.left.arrow.right.circle"], title: "Les deux à la fois", detail: "Ce Mac reçoit et envoie en même temps.") {
                    controller.receiveArmed = true; controller.sendArmed = true
                }
            }
        }
        .padding(.vertical, compact ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
    }
}

/// A large tile that arms a direction.
struct ChoiceTile: View {
    /// The picto of the tile: a direction, or the one for both.
    let symbols: [String]
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void
    @Environment(\.appAccentColor) private var accent
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbols[0]).font(.system(size: 34, weight: .regular))
                    .frame(width: 72, height: 72)
                    .background(Color.primary.opacity(hovered ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(hovered ? accent : Color.primary)
                Text(title).font(.title3).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 226, height: 250).padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(hovered ? 0.05 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hovered ? accent.opacity(0.7) : Color.primary.opacity(0.14), lineWidth: hovered ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
        .accessibilityLabel(title)
    }
}
