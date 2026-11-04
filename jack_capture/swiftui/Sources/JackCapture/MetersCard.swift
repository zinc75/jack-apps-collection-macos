// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import MeterKit
import JackCaptureKit

/// The levels of the channels while the recording runs, read from the console meter of jack_capture: one bar per
/// channel on the same IEC scale, a tick for the peak it holds, a mark when a channel clipped.
struct MetersCard: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Niveaux d'entrée").fontWeight(.semibold)
                if model.settings.metersEnabled {
                    MeterBars(meters: model.meters, channels: model.settings.channels, scale: IECScale(), label: "Niveaux d'entrée")
                } else {
                    Text("Les vumètres sont désactivés. Ils se règlent dans Configuration, Affichage.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}
