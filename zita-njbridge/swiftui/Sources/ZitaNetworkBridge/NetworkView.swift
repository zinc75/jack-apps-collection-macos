// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

struct NetworkView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        SettingsPage {
            Text("Réseau").font(.title2).fontWeight(.semibold)
            Text("Chaque Mac écoute sur sa propre adresse et envoie vers celle de l'autre. Les adresses se saisissent à la main.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, -14)
            if controller.armedDirections.isEmpty {
                Text("Choisissez **Recevoir**, **Envoyer** ou les deux, dans le pied de la fenêtre.").foregroundStyle(.secondary)
            }
            if controller.receiveArmed { ReceiveNetworkGroup() }
            if controller.sendArmed { SendNetworkGroup() }
            GroupNote(text: "Un câble direct entre deux Macs n'a pas de serveur d'adresses : donnez à chaque Mac une adresse de la même base (par exemple 10.10.10.1 et 10.10.10.2).")
        }
    }
}

// MARK: Receiving

struct ReceiveNetworkGroup: View {
    @Environment(AppModel.self) private var model
    @State private var choices = [NetworkAddress]()
    @State private var interfaces = [NetworkInterface]()
    @State private var copied = false

    var body: some View {
        @Bindable var receiver = model.controller.receiver
        SettingsGroup("Réception : ce Mac écoute", systemImage: LinkDirection.receive.symbol) {
            OptionRow("Adresse d'écoute",
                      receiver.settings.multicast ? "L'adresse du groupe de multidiffusion." : "Une adresse de ce Mac. C'est celle à donner à l'émetteur.") {
                if receiver.settings.multicast {
                    TextField("Adresse du groupe", text: $receiver.settings.address)
                        .labelsHidden().frame(width: 220).autocorrectionDisabled()
                } else {
                    Picker("Adresse d'écoute", selection: $receiver.settings.address) {
                        if receiver.settings.address.isEmpty { Text("Choisir une adresse…").tag("") }
                        if !receiver.settings.address.isEmpty, !choices.contains(where: { $0.address == receiver.settings.address }) {
                            Text("\(receiver.settings.address) · absente").tag(receiver.settings.address)
                        }
                        ForEach(choices) { Text(label($0)).tag($0.address) }
                    }
                    .labelsHidden().frame(width: 270, alignment: .trailing)
                    Button(copied ? "Copié" : "Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(receiver.settings.address, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                    }
                    .fixedSize()
                    .disabled(receiver.settings.address.isEmpty)
                }
            }
            OptionRow("Port") { NumberField(label: "Port", value: $receiver.settings.port, range: 1...65535) }
            OptionRow("Multidiffusion", "Un émetteur pour plusieurs récepteurs. L'adresse est alors une adresse de groupe, et l'interface réseau est obligatoire.") {
                Toggle("Multidiffusion", isOn: $receiver.settings.multicast).labelsHidden().toggleStyle(.switch).accentTint()
            }
            if receiver.settings.multicast {
                OptionRow("Interface réseau") {
                    InterfacePicker(selection: $receiver.settings.interface, interfaces: interfaces)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                let all = NetworkInventory.interfaces()
                interfaces = NetworkInventory.multicastChoices(from: all)
                choices = NetworkInventory.listenChoices(from: all)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// "10.10.10.1 · USB 10/100/1000 LAN", with a word more for an address that the Mac made for itself on a cable.
    private func label(_ a: NetworkAddress) -> String {
        let name = interfaceName(a.interface)
        let note = a.kind == .linkLocal ? " · " + String(localized: "adresse locale de lien") : ""
        return "\(a.address.split(separator: "%").first.map(String.init) ?? a.address) · \(name)\(note)"
    }

    private func interfaceName(_ bsd: String) -> String {
        interfaces.first { $0.name == bsd }?.displayName ?? bsd
    }
}

/// The interfaces a multicast link can use, by the name System Settings gives them.
struct InterfacePicker: View {
    @Binding var selection: String
    let interfaces: [NetworkInterface]

    var body: some View {
        Picker("Interface réseau", selection: $selection) {
            if selection.isEmpty { Text("Choisir une interface…").tag("") }
            if !selection.isEmpty, !interfaces.contains(where: { $0.name == selection }) { Text("\(selection) · absente").tag(selection) }
            ForEach(interfaces) { Text("\($0.name) · \($0.displayName)").tag($0.name) }
        }
        .labelsHidden().frame(width: 330, alignment: .trailing)
    }
}

// MARK: Sending

struct SendNetworkGroup: View {
    @Environment(AppModel.self) private var model
    @State private var interfaces = [NetworkInterface]()
    @State private var ping = PingState.idle

    enum PingState: Equatable { case idle, running, done(PingOutcome) }

    var body: some View {
        @Bindable var sender = model.controller.sender
        SettingsGroup("Envoi : vers l'autre Mac", systemImage: LinkDirection.send.symbol) {
            OptionRow("Adresse du récepteur", "L'adresse de l'autre Mac : adresse IP ou nom de machine.") {
                TextField("Adresse du récepteur", text: $sender.settings.address)
                    .labelsHidden().frame(width: 220).autocorrectionDisabled()
                    .onChange(of: sender.settings.address) { _, _ in ping = .idle }
            }
            OptionRow("Port") { NumberField(label: "Port", value: $sender.settings.port, range: 1...65535) }
            OptionRow("Multidiffusion", "Un émetteur pour plusieurs récepteurs. L'adresse est alors une adresse de groupe, et l'interface réseau est obligatoire.") {
                Toggle("Multidiffusion", isOn: $sender.settings.multicast).labelsHidden().toggleStyle(.switch).accentTint()
            }
            if sender.settings.multicast {
                OptionRow("Interface réseau") {
                    InterfacePicker(selection: $sender.settings.interface, interfaces: interfaces)
                }
            }
            OptionRow("Joindre le récepteur",
                      sender.settings.multicast ? "Sans objet en multidiffusion."
                      : "Un ping vers l'adresse du récepteur : il vérifie que l'autre Mac répond, pas que le port est ouvert.") {
                pingResult
                Button("Envoyer un ping") { runPing(sender.settings) }
                    .disabled(sender.settings.multicast || sender.settings.address.trimmingCharacters(in: .whitespaces).isEmpty || ping == .running)
            }
        }
        .task {
            while !Task.isCancelled {
                interfaces = NetworkInventory.multicastChoices()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ViewBuilder private var pingResult: some View {
        switch ping {
        case .idle: EmptyView()
        case .running: Chip(text: Text("Ping en cours…"))
        case .done(let outcome):
            switch outcome {
            case .replied(let r):
                let average = r.average.map { ($0).formatted(.number.precision(.fractionLength(1))) } ?? "?"
                Chip(text: Text("Répond en \(average) ms · \(r.lossPercent.formatted(.number.precision(.fractionLength(0...1)))) % de perte"), kind: r.lossPercent > 0 ? .warn : .ok)
            case .noAnswer: Chip(text: Text("Ne répond pas"), kind: .warn)
            case .unknownHost: Chip(text: Text("Nom inconnu"), kind: .bad)
            case .unreachable(let reason): Chip(text: Text(verbatim: reason), kind: .bad)
            case .failed(let text): Chip(text: Text(verbatim: text), kind: .bad)
            }
        }
    }

    private func runPing(_ settings: SendSettings) {
        ping = .running
        Task {
            let outcome = await Pinger.ping(host: settings.address, ipVersion: settings.ipVersion)
            ping = .done(outcome)
        }
    }
}
