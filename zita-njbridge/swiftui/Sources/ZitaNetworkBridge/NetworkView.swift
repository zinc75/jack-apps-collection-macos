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
                NoDirectionView(compact: true)
            }
            if controller.receiveArmed { ReceiveNetworkGroup() }
            if controller.sendArmed { SendNetworkGroup() }
            GroupNote(text: "Un câble direct entre deux Macs n'a pas de serveur d'adresses : donnez à chaque Mac une adresse de la même base (par exemple 10.10.10.1 et 10.10.10.2).")
            GroupNote(text: "Multidiffusion : pour atteindre plusieurs récepteurs d'un coup, l'émetteur et chaque récepteur utilisent la même adresse de groupe (de 224.0.0.0 à 239.255.255.255), chacun avec son interface réseau. Il suffit de saisir une adresse de groupe : la multidiffusion s'active toute seule.")
        }
    }
}

// MARK: Receiving

struct ReceiveNetworkGroup: View {
    @Environment(AppModel.self) private var model
    @State private var choices = [NetworkAddress]()
    @State private var interfaces = [NetworkInterface]()
    @State private var linkLocal = [NetworkInterface]()
    @State private var copied = false

    var body: some View {
        @Bindable var receiver = model.controller.receiver
        SettingsGroup(direction: .receive, detail: "Ce Mac écoute le réseau") {
            OptionRow("Adresse d'écoute",
                      receiver.settings.multicast
                      ? "Une adresse de groupe de multidiffusion : tous les récepteurs écoutent la même."
                      : "Une adresse de ce Mac, à donner à l'émetteur. Une adresse de groupe de multidiffusion convient aussi.") {
                // The address is typed, or taken from the addresses of this Mac in the menu. A group address makes the link multicast.
                TextField("Adresse de ce Mac ou du groupe", text: $receiver.settings.address)
                    .labelsHidden().frame(width: 200).autocorrectionDisabled()
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(addressProblem(receiver.settings.address, notFound: receiver.addressNotFound) != nil ? Color.alert : .clear, lineWidth: 1).padding(-1))
                // A pop-up button with its name, not an icon: it says what it holds, and keeps the name of the network of each address.
                Menu("Adresses de ce Mac") {
                    ForEach(choices) { choice in Button(label(choice)) { receiver.settings.address = choice.address } }
                }
                .fixedSize()
                .help("Choisir une des adresses de ce Mac")
                .disabled(choices.isEmpty)
                // An icon of a fixed size: the button does not change its width when it confirms, and the pointer tells what it does.
                Button {
                    NSPasteboard.general.clearContents()
                    // The interface after a "%" belongs to this Mac: the other one has its own, so it is not given.
                    NSPasteboard.general.setString(LinkLocalAddress.withoutZone(receiver.settings.address), forType: .string)
                    withAnimation { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 16)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Copier l'adresse")
                .accessibilityLabel("Copier l'adresse")
                .disabled(receiver.settings.address.isEmpty)
            }
            if let problem = addressProblem(receiver.settings.address, notFound: receiver.addressNotFound) { AddressProblemNote(text: problem) }
            if LinkLocalAddress.lacksZone(receiver.settings.address) { ZoneHint(address: $receiver.settings.address, candidates: linkLocal) }
            OptionRow("Port") { NumberField(label: "Port", value: $receiver.settings.port, range: 1...65535) }
            if receiver.settings.multicast {
                OptionRow("Interface réseau", "Obligatoire en multidiffusion : l'interface par laquelle ce Mac rejoint le groupe.") {
                    InterfacePicker(selection: $receiver.settings.interface, interfaces: interfaces)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                let all = NetworkInventory.interfaces()
                interfaces = NetworkInventory.multicastChoices(from: all)
                linkLocal = NetworkInventory.linkLocalInterfaces(from: all)
                choices = NetworkInventory.listenChoices(from: all)
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: receiver.settings.address) { await deduceMulticast() }
    }

    /// The address decides: a group address (or a name that resolves to one) makes the link multicast, which needs an interface; the first one
    /// is taken when none is chosen.
    private func deduceMulticast() async {
        let address = model.controller.receiver.settings.address
        model.controller.receiver.addressNotFound = false   // until it is found out again
        try? await Task.sleep(for: .milliseconds(400))   // not for each key typed
        let resolved = await MulticastAddress.isGroupResolving(address)
        let group = resolved ?? false
        let r = model.controller.receiver
        guard r.settings.address == address else { return }
        // A name that does not resolve is not an address of any machine: the program would stop at once.
        r.addressNotFound = AddressCheck.syntax(of: address) == .hostname && resolved == nil
        if r.settings.multicast != group { r.settings.multicast = group }
        if group, r.settings.interface.isEmpty, let first = interfaces.first { r.settings.interface = first.name }
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

/// What is wrong with an address typed, if anything: not an address nor a name, or a name that no machine answers to.
@MainActor
func addressProblem(_ address: String, notFound: Bool) -> LocalizedStringKey? {
    switch AddressCheck.syntax(of: address) {
    case .invalid: return "Ce n'est ni une adresse IPv4 (10.10.10.1), ni une adresse IPv6 (fe80::1%en0), ni un nom de machine."
    case .hostname where notFound: return "Aucune machine ne répond à ce nom."
    default: return nil
    }
}

/// The problem of an address, under its field.
struct AddressProblemNote: View {
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(Color.alert)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// A link-local IPv6 address was typed without its interface: it is completed with an interface of this Mac (the one of the cable).
struct ZoneHint: View {
    @Binding var address: String
    let candidates: [NetworkInterface]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Une adresse locale de lien IPv6 doit dire par quelle interface de ce Mac elle se joint : elle se termine par un « % » et le nom de l'interface.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if candidates.count == 1, let one = candidates.first {
                Button("Ajouter %\(one.name)") { address = LinkLocalAddress.adding(zone: one.name, to: address) }
            } else if candidates.count > 1 {
                Menu("Ajouter l'interface…") {
                    ForEach(candidates) { i in Button("\(i.name) · \(i.displayName)") { address = LinkLocalAddress.adding(zone: i.name, to: address) } }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
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
    @State private var linkLocal = [NetworkInterface]()
    @State private var ping = PingState.idle

    enum PingState: Equatable { case idle, running, done(PingOutcome) }

    var body: some View {
        @Bindable var sender = model.controller.sender
        SettingsGroup(direction: .send, detail: "Vers l'autre Mac") {
            // In multicast there is no address for each receiver: one address of a group is sent to, and every receiver listens to it.
            OptionRow(sender.settings.multicast ? "Adresse du groupe" : "Adresse du récepteur",
                      sender.settings.multicast
                      ? "Une seule adresse pour tous les récepteurs : ils écoutent tous cette adresse de groupe."
                      : "L'adresse de l'autre Mac (adresse IP ou nom de machine), ou une adresse de groupe de multidiffusion pour plusieurs récepteurs.") {
                TextField(sender.settings.multicast ? "Adresse du groupe" : "Adresse du récepteur ou du groupe", text: $sender.settings.address)
                    .labelsHidden().frame(width: 220).autocorrectionDisabled()
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(addressProblem(sender.settings.address, notFound: sender.addressNotFound) != nil ? Color.alert : .clear, lineWidth: 1).padding(-1))
                    .onChange(of: sender.settings.address) { _, _ in ping = .idle }
            }
            if let problem = addressProblem(sender.settings.address, notFound: sender.addressNotFound) { AddressProblemNote(text: problem) }
            if LinkLocalAddress.lacksZone(sender.settings.address) { ZoneHint(address: $sender.settings.address, candidates: linkLocal) }
            OptionRow("Port") { NumberField(label: "Port", value: $sender.settings.port, range: 1...65535) }
            if sender.settings.multicast {
                OptionRow("Interface réseau", "Obligatoire en multidiffusion : l'interface par laquelle ce Mac envoie au groupe.") {
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
                let all = NetworkInventory.interfaces()
                interfaces = NetworkInventory.multicastChoices(from: all)
                linkLocal = NetworkInventory.linkLocalInterfaces(from: all)
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: sender.settings.address) { await deduceMulticast() }
    }

    /// The address decides: a group address (or a name that resolves to one) makes the link multicast, which needs an interface.
    private func deduceMulticast() async {
        let address = model.controller.sender.settings.address
        model.controller.sender.addressNotFound = false   // until it is found out again
        try? await Task.sleep(for: .milliseconds(400))
        let resolved = await MulticastAddress.isGroupResolving(address)
        let group = resolved ?? false
        let s = model.controller.sender
        guard s.settings.address == address else { return }
        s.addressNotFound = AddressCheck.syntax(of: address) == .hostname && resolved == nil
        if s.settings.multicast != group { s.settings.multicast = group }
        if group, s.settings.interface.isEmpty, let first = interfaces.first { s.settings.interface = first.name }
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
