// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

/// The pages of the window: the recording first, then the sections of the settings.
struct Sidebar: View {
    @Environment(RecorderModel.self) private var model

    private var selection: Binding<MainView?> {
        Binding(get: { model.view }, set: { if let page = $0 { model.view = page } })
    }

    var body: some View {
        List(selection: selection) {
            Label("Enregistrement", systemImage: "record.circle").tag(MainView.recording)
            Section("Réglages") {
                Label("Voies", systemImage: "circle.grid.3x3").tag(MainView.channels)
                    // Draws the eye to the matrix while some channels would be silent, before any recording.
                    .overlay { if model.view != .channels && !model.sourceCheck.isClean { PulsingOutline(color: .alert, radius: 6).padding(-3) } }
                Label("Fichier", systemImage: "doc").tag(MainView.file)
                Label("Démarrage et arrêt", systemImage: "timer").tag(MainView.startStop)
                Label("Avancé", systemImage: "slider.horizontal.3").tag(MainView.advanced)
                Label("Affichage", systemImage: "eye").tag(MainView.display)
            }
        }
        .listStyle(.sidebar)
    }
}
