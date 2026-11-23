// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        List {
            row("Accueil", "house", .home)
            row("Convolutions", "square.grid.3x3", .matrix).disabled(!model.isOpen)
            row("Analyse", "waveform.path.ecg", .impulse).disabled(!model.isOpen)
            if model.mode == .realTime { row("Connexions", "arrow.left.arrow.right", .ports, badge: model.connectionsNeedAttention && model.page != .ports ? .orange : nil).disabled(!model.isOpen) }
            if model.mode == .realTime { row("Lancement", "slider.horizontal.3", .launch).disabled(!model.isOpen) }
            row("Fichier de configuration", "doc.plaintext", .config).disabled(!model.isOpen)
            row("Journal", "doc.text", .log, badge: logBadge).disabled(!model.isOpen)
            row("Affichage", "circle.lefthalf.filled", .display)
        }
        .listStyle(.sidebar)
        .inactiveSidebarFill()
    }

    /// A dot on the journal while it holds a warning or an error that has not been looked at.
    private var logBadge: Color? {
        guard model.page != .log else { return nil }
        let entries = model.controller.log.entries
        if entries.contains(where: { $0.severity == .error && $0.id >= model.logSeen }) { return .red }
        if entries.contains(where: { $0.severity == .warning && $0.id >= model.logSeen }) { return .orange }
        return nil
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ page: Page, badge: Color? = nil) -> some View {
        let selected = model.page == page
        return Button { model.page = page } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer(minLength: 4)
                if let badge { Circle().fill(badge).frame(width: 8, height: 8) }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(selected ? accent : .clear).padding(.horizontal, 10))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
