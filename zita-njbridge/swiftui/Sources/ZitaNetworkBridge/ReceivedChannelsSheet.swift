// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI
import ZitaBridgeKit

/// Which channels the receiver takes, opened from the page of the lanes. By default all of the sender's; choosing is for a receiver among
/// several that each take a part of a large stream.
struct ReceivedChannelsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var receiver = model.controller.receiver
        let sent = receiver.sender?.channels
        VStack(alignment: .leading, spacing: 18) {
            DirectionTitle(direction: .receive, detail: "Voies reçues")
            Text("Par défaut, le récepteur prend toutes les voies de l'émetteur. Pour partager un grand flux entre plusieurs récepteurs, choisissez seulement les voies de celui-ci : les autres ne sont pas créées dans JACK.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Voies reçues", selection: Binding(
                get: { receiver.settings.automaticChannels },
                set: { automatic in
                    let current = receiver.settings.effectiveChannels
                    receiver.settings.automaticChannels = automatic
                    if !automatic { receiver.settings.channels = current }
                })) {
                Text("Toutes celles de l'émetteur").tag(true)
                Text("Choisir").tag(false)
            }
            .labelsHidden().pickerStyle(.segmented).accentTint()
            if receiver.settings.automaticChannels {
                Text(automaticNote(last: receiver.settings.knownSenderChannels, heard: sent)).font(.callout).foregroundStyle(.secondary)
            } else {
                ChannelGrid(selection: $receiver.settings.channels, available: sent)
            }
            HStack {
                Spacer()
                Button("Terminé") { dismiss() }.keyboardShortcut(.defaultAction).accentTint()
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func automaticNote(last: Int, heard: Int?) -> LocalizedStringKey {
        if let heard { return "L'émetteur envoie \(heard) voies en ce moment : elles sont toutes reçues." }
        return "L'émetteur avait \(last) voies la dernière fois. Le récepteur s'adapte dès qu'il l'entend."
    }
}

/// The channels of the stream as numbered buttons, eight to a row, to switch on or off. Those beyond what the sender sends, once it is
/// heard, cannot be chosen: they would be silent.
struct ChannelGrid: View {
    @Binding var selection: [Int]
    let available: Int?
    @State private var extraRows = 0
    @Environment(\.appAccentColor) private var accent

    private var shown: Int {
        let needed = max(selection.max() ?? 0, available ?? 0, 16)
        return min(ChannelList.maximum, ((needed + 7) / 8) * 8 + extraRows * 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                ForEach(1...shown, id: \.self) { channel in chip(channel) }
            }
            HStack(spacing: 8) {
                Button("Tout") { selection = Array(1...max(1, min(available ?? shown, ChannelList.maximum))) }
                Button("Stéréo (1-2)") { selection = [1, 2] }
                if shown < ChannelList.maximum { Button("Plus de voies") { extraRows += 1 } }
                Spacer()
                Text("Voies : \(ChannelList.format(selection))").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ channel: Int) -> some View {
        let on = selection.contains(channel)
        let silent = available.map { channel > $0 } ?? false
        return Button { toggle(channel) } label: {
            Text(verbatim: "\(channel)").font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: 40, height: 28)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? accent : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .opacity(silent ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(silent && !on)
        .help(silent ? "L'émetteur n'envoie que \(available ?? 0) voies." : "")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// At least one channel stays chosen.
    private func toggle(_ channel: Int) {
        var set = Set(selection)
        if set.contains(channel) { if set.count > 1 { set.remove(channel) } } else { set.insert(channel) }
        selection = set.sorted()
    }
}
