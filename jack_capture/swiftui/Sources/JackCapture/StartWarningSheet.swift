// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import JackCaptureKit

/// Asked when the red button is pressed while some channels would come out silent.
struct StartWarningSheet: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Label("Des voies seraient muettes", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Color.alert)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.sourceCheck.descriptions, id: \.self) { Text($0) }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Annuler") { model.asksToConfirm = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer quand même") { model.startAnyway() }
                Button("Choisir les sources…") {
                    model.asksToConfirm = false
                    model.view = .channels
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
