// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Said on the pages that change the configuration while the engine runs: it is only looked at.
struct LockBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isLocked {
            Label("Moteur en marche : la configuration est en lecture seule. Arrêtez-le pour la modifier.", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
