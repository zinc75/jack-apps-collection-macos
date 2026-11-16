// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        List {
            row("Lecture", "play.circle", .play)
            Section("Réglages") {
                row("Sorties", "circle.grid.3x3", .outputs)
                row("Boucle et transport", "repeat", .loop)
                row("Avancé", "slider.horizontal.3", .advanced)
                row("Affichage", "eye", .display)
            }
        }
        .listStyle(.sidebar)
        .inactiveSidebarFill()
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ page: Page) -> some View {
        let selected = model.page == page
        return Button { model.page = page } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(selected ? accent : .clear).padding(.horizontal, 10))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
