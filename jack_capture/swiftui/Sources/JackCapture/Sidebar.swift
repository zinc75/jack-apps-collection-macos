// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

/// The pages of the window: the recording first, then the sections of the settings.
struct Sidebar: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        // The selection is drawn here, in the accent of the application: the one of a sidebar follows the accent of macOS.
        List {
            row("Enregistrement", "record.circle", .recording)
            Section("Réglages") {
                // Draws the eye to the matrix while some channels would be silent, before any recording.
                row("Voies", "circle.grid.3x3", .channels, pulses: model.view != .channels && !model.sourceCheck.isClean)
                row("Fichier", "doc", .file)
                row("Démarrage et arrêt", "timer", .startStop)
                row("Avancé", "slider.horizontal.3", .advanced)
                row("Affichage", "eye", .display)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ page: MainView, pulses: Bool = false) -> some View {
        let selected = model.view == page
        return Button { model.view = page } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay { if pulses { PulsingOutline(color: .alert, radius: 6).padding(-3) } }
        }
        .buttonStyle(.plain)
        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(selected ? accent : .clear).padding(.horizontal, 10))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
