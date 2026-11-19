// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// The format that is sent and the reserve of the receiver's buffer, and what is common to both.
struct FlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        SettingsPage {
            VStack(alignment: .leading, spacing: 2) {
                Text("Flux").font(.title2).fontWeight(.semibold)
                Text("Le format envoyé, et la réserve de tampon du récepteur.").font(.callout).foregroundStyle(.secondary)
            }
            if controller.armedDirections.isEmpty {
                Text("Choisissez **Recevoir**, **Envoyer** ou les deux, dans le pied de la fenêtre.").foregroundStyle(.secondary)
            }
            if controller.receiveArmed { BufferGroup() }
            if controller.sendArmed { SendFormatGroup() }
            AdvancedGroup()
            ClientNamesGroup()
        }
    }
}

private func milliseconds(_ frames: Int, rate: Int) -> String {
    (Double(frames) / Double(rate) * 1000).formatted(.number.precision(.fractionLength(1)))
}

// MARK: Receiver buffer

struct BufferGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var receiver = model.controller.receiver
        let graph = model.controller.graph
        let period = graph.bufferSize, rate = graph.sampleRate
        let advised = period.map { BufferAdvice.recommendedMilliseconds(period: $0) }
        SettingsGroup("Tampon du récepteur", systemImage: LinkDirection.receive.symbol) {
            OptionRow("Tampon supplémentaire", "Ajoute de la latence, absorbe les retards du réseau. Par défaut : 10 ms.") {
                Slider(value: Binding(get: { Double(receiver.settings.bufferMilliseconds) }, set: { receiver.settings.bufferMilliseconds = Int($0) }),
                       in: 0...120, step: 1)
                    .frame(width: 200).accentTint()
                Text("\(receiver.settings.bufferMilliseconds) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
            OptionRow("Suggestion", suggestion(period: period, rate: rate, advised: advised)) {
                Button("Appliquer") { if let advised { receiver.settings.bufferMilliseconds = advised } }
                    .disabled(advised == nil || receiver.settings.bufferMilliseconds >= (advised ?? 0))
            }
            OptionRow("Filtre de rééchantillonnage",
                      "Plus il est long, plus la bande passante est plate jusqu'aux aigus, au prix de latence et de calcul. Automatique : choisi selon la plus basse des deux fréquences.") {
                Picker("Filtre", selection: Binding(get: { receiver.settings.filterDelay == nil }, set: { auto in
                    receiver.settings.filterDelay = auto ? nil : automaticFilter(receiver.sender?.rate, rate)
                })) {
                    Text("Automatique").tag(true)
                    Text("Manuel").tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize().accentTint()
            }
            if let delay = receiver.settings.filterDelay {
                OptionRow("Longueur du filtre", filterNote(delay, rate, receiver.sender?.rate)) {
                    Stepper(value: Binding(get: { delay }, set: { receiver.settings.filterDelay = $0 }), in: 16...96, step: 4) {
                        Text(verbatim: "\(delay)").monospacedDigit().frame(minWidth: 26, alignment: .trailing)
                    }
                    Text("échantillons, de 16 à 96").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func automaticFilter(_ sender: Int?, _ local: Int?) -> Int {
        guard let local else { return 32 }
        return BufferAdvice.automaticFilterDelay(localRate: local, senderRate: sender ?? local)
    }

    private func suggestion(period: Int?, rate: Int?, advised: Int?) -> LocalizedStringKey {
        guard let period, let rate, let advised else { return "Démarrez JACK pour connaître la période et obtenir une suggestion." }
        let per = milliseconds(period, rate: rate)
        let estimate = BufferAdvice.isMeasured(period: period)
        return estimate
            ? "Période JACK : \(period.formatted(.number.grouping(.automatic))) trames (\(per) ms). Recommandé : **\(advised) ms** ou plus."
            : "Période JACK : \(period.formatted(.number.grouping(.automatic))) trames (\(per) ms). Estimation, non mesurée : **\(advised) ms** ou plus."
    }

    private func filterNote(_ delay: Int, _ local: Int?, _ sender: Int?) -> LocalizedStringKey {
        guard let local else { return "Latence ajoutée : \(delay) échantillons." }
        let auto = BufferAdvice.automaticFilterDelay(localRate: local, senderRate: sender ?? local)
        return "Latence ajoutée : \(milliseconds(delay, rate: local)) ms (\(delay) échantillons à \(local.formatted(.number.grouping(.automatic))) Hz). Automatique : \(auto)."
    }
}

// MARK: Sender format

struct SendFormatGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var sender = model.controller.sender
        SettingsGroup("Format envoyé", systemImage: LinkDirection.send.symbol) {
            OptionRow("Échantillons", "24 bits est le choix usuel. Flottant 32 bits conserve le format interne de JACK, avec un débit plus grand.") {
                Picker("Échantillons", selection: $sender.settings.format) {
                    Text("16 bits").tag(SampleFormat.bits16)
                    Text("24 bits").tag(SampleFormat.bits24)
                    Text("Flottant").tag(SampleFormat.float32)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize().accentTint()
            }
            OptionRow("Taille maximale d'un paquet", "1 500 octets sur un réseau ordinaire. Des paquets plus grands augmentent la gigue sur un réseau partagé.") {
                NumberField(label: "Taille maximale d'un paquet", value: $sender.settings.packetSize, range: 576...9216)
            }
            if sender.settings.multicast {
                OptionRow("Sauts de multidiffusion", "1 : le réseau local seulement.") {
                    NumberField(label: "Sauts", value: $sender.settings.hops, range: 1...255, width: 70)
                }
            }
        }
    }
}

// MARK: Common

struct AdvancedGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        SettingsGroup("Avancé") {
            OptionRow("Version du protocole IP",
                      "Utile seulement avec un nom de machine qui peut se résoudre en IPv4 et en IPv6 : forcer l'IPv4 ou l'IPv6. Automatique convient à une adresse numérique.") {
                Picker("Version du protocole IP", selection: Binding(
                    get: { controller.receiveArmed ? controller.receiver.settings.ipVersion : controller.sender.settings.ipVersion },
                    set: { controller.receiver.settings.ipVersion = $0; controller.sender.settings.ipVersion = $0 })) {
                    Text("Automatique").tag(IPVersion.automatic)
                    Text("IPv4").tag(IPVersion.ipv4)
                    Text("IPv6").tag(IPVersion.ipv6)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize().accentTint()
            }
        }
    }
}

struct ClientNamesGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var receiver = model.controller.receiver
        @Bindable var sender = model.controller.sender
        let controller = model.controller
        SettingsGroup("Clients JACK") {
            if controller.receiveArmed {
                OptionRow("Nom du client de réception", systemImage: LinkDirection.receive.symbol) {
                    NameField(label: "Nom du client de réception", text: $receiver.settings.clientName)
                }
            }
            if controller.sendArmed {
                OptionRow("Nom du client d'envoi", systemImage: LinkDirection.send.symbol) {
                    NameField(label: "Nom du client d'envoi", text: $sender.settings.clientName)
                }
            }
        }
    }
}

/// A name, kept apart while it is typed: an empty name is not taken, and the last good one comes back when the field is left.
struct NameField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $draft)
            .labelsHidden().frame(width: 200).autocorrectionDisabled()
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: draft) { _, new in if !new.trimmingCharacters(in: .whitespaces).isEmpty { text = new } }
            .onChange(of: text) { _, new in if new != draft, !focused { draft = new } }
            .onChange(of: focused) { _, now in if !now { draft = text } }
    }
}

// MARK: Display

struct DisplayView: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        SettingsPage {
            Text("Affichage").font(.title2).fontWeight(.semibold)
            SettingsGroup("Apparence") {
                OptionRow("Apparence") { AppearanceModePicker(settings: appearance) }
                OptionRow("Couleur d'accent") { AccentSwatches(settings: appearance) }
            }
        }
    }
}
