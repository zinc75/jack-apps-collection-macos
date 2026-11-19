// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackBridge
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// The channels of each direction wired to the ports of the other clients. The columns are the channels of the program
/// (`in_N` of the sender, `out_N` of the receiver), the rows are the ports of the other clients: the same in both directions.
struct LanesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        SettingsPage {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voies").font(.title2).fontWeight(.semibold)
                Text("Les branchements sont mémorisés. Ils sont refaits dès que la liaison démarre.").font(.callout).foregroundStyle(.secondary)
            }
            if controller.armedDirections.isEmpty {
                NoDirectionView(compact: true)
            }
            if controller.receiveArmed { LanesBlock(direction: .receive) }
            if controller.sendArmed { LanesBlock(direction: .send) }
        }
    }
}

struct LanesBlock: View {
    let direction: LinkDirection
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []
    @State private var showsChannels = false

    private static let nameWidth: CGFloat = 220, cellWidth: CGFloat = 40

    var body: some View {
        let controller = model.controller
        let channels = controller.channels(for: direction)
        let clients = direction == .receive ? controller.graph.destinations : controller.graph.sources
        let wiring = controller.wiring(for: direction)
        DirectionContainer(direction: direction, detail: direction == .receive ? "Du réseau vers JACK" : "De JACK vers le réseau") {
            Text(direction == .receive
                 ? "Chaque sortie de zita-n2j est reliée aux ports JACK de votre choix. Les voies que l'émetteur n'envoie pas restent silencieuses."
                 : "Chaque entrée de zita-j2n est reliée aux ports JACK de votre choix.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if direction == .receive {
                    let receiver = controller.receiver
                    // Which channels the receiver takes is set in the advanced settings of the flow; here, what it does now.
                    Text(receiver.settings.automaticChannels
                         ? "Voies reçues : toutes celles de l'émetteur (\(receiver.settings.effectiveChannels.count))"
                         : "Voies reçues : \(ChannelList.format(receiver.settings.effectiveChannels))")
                        .foregroundStyle(.secondary)
                    Button("Régler les voies reçues…") { showsChannels = true }
                } else {
                    Text("Nombre de voies").foregroundStyle(.secondary)
                    Stepper(value: channelCount, in: 1...ChannelList.maximum) { Text(verbatim: "\(channels.count)").monospacedDigit().frame(minWidth: 22, alignment: .trailing) }
                    Text("jusqu'à 64").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                // One control for both ways of starting again, instead of two buttons.
                Menu("Réinitialiser") {
                    Button("Effacer tous les branchements") { controller.clearWiring(direction) }
                    Button(direction == .receive ? "Revenir à la sortie système" : "Revenir à l'entrée système") { controller.wireToSoundCard(direction) }
                }
                .fixedSize()
                .help("Efface les branchements, ou remet chaque voie sur le port du même numéro de la carte son (voie 1 sur le port 1, voie 2 sur le port 2…).")
            }
            if clients.isEmpty {
                Text(direction == .receive ? "Aucune entrée audio dans le graphe JACK." : "Aucune sortie audio dans le graphe JACK.").foregroundStyle(.secondary)
            } else {
                matrix(clients: clients, channels: channels, wiring: wiring).frame(height: min(400, height(clients))).blockBackground()
            }
            hint(channels: channels, wiring: wiring)
        }
        .sheet(isPresented: $showsChannels) { ReceivedChannelsSheet() }
        #if DEBUG
        .task { if direction == .receive, ProcessInfo.processInfo.environment["ZITABRIDGE_SHEET"] != nil { try? await Task.sleep(for: .seconds(2)); showsChannels = true } }
        #endif
    }

    /// The number of channels of the sender: it sends channels 1 to N.
    private var channelCount: Binding<Int> {
        let controller = model.controller
        return Binding(get: { controller.sender.settings.channels }, set: { controller.sender.settings.channels = $0 })
    }

    private func height(_ clients: [JackPortClient]) -> CGFloat {
        clients.reduce(CGFloat(40)) { $0 + 44 + (collapsed.contains($1.name) ? 0 : CGFloat($1.ports.count) * 31) }
    }

    private func matrix(clients: [JackPortClient], channels: [Int], wiring: ChannelWiring) -> some View {
        let controller = model.controller
        let width = Self.nameWidth + Self.cellWidth * CGFloat(channels.count)
        let portName = direction == .receive ? "out" : "in"
        return GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text(direction == .receive ? "Ports JACK de destination" : "Ports JACK de source").font(.callout).foregroundStyle(.secondary)
                            .padding(.leading, 14).frame(width: Self.nameWidth, alignment: .leading)
                        ForEach(channels, id: \.self) { channel in
                            VStack(spacing: 2) {
                                ChannelNumber(number: channel, warns: (wiring.ports[channel] ?? []).isEmpty)
                                Text(verbatim: "\(portName)_\(channel)").font(.system(size: 9.5)).foregroundStyle(.secondary)
                            }
                            .frame(width: Self.cellWidth)
                        }
                    }
                    .frame(width: width, height: 40, alignment: .leading)
                    ForEach(clients) { client in
                        let open = !collapsed.contains(client.name)
                        Button {
                            if open { collapsed.insert(client.name) } else { collapsed.remove(client.name) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 0 : -90)).frame(width: 12)
                                BadgeView(client: client.name, isCapture: direction == .send && client.isSystem, isPlayback: direction == .receive && client.isSystem,
                                          isJackMoebiusMaster: client.isJackMoebiusMaster, size: 28, bundleID: client.bundleID)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: displayName(client)).fontWeight(.semibold)
                                    Text(portCount(client.ports.count)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .frame(width: width, alignment: .leading)
                            .background(Color.primary.opacity(0.06))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if open {
                            ForEach(client.ports, id: \.self) { port in
                                let full = client.fullName(of: port)
                                Divider().frame(width: width)
                                HStack(spacing: 0) {
                                    Text(verbatim: port).font(.system(size: 12.5)).lineLimit(1)
                                        .padding(.leading, 30).frame(width: Self.nameWidth, alignment: .leading)
                                    ForEach(channels, id: \.self) { channel in
                                        AccentLED(isOn: wiring.contains(channel: channel, port: full)) {
                                            controller.toggleWire(direction, channel: channel, port: full)
                                        }
                                    }
                                }
                                .frame(width: width, height: 30, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
    }

    private func displayName(_ client: JackPortClient) -> String {
        guard client.isSystem else { return client.name }
        return direction == .receive ? "system (playback)" : "system (capture)"
    }

    private func portCount(_ n: Int) -> String {
        n == 1 ? String(localized: "1 port") : String(localized: "\(n) ports")
    }

    private func hint(channels: [Int], wiring: ChannelWiring) -> some View {
        let unwired = wiring.unwired(in: channels)
        let base: Text
        if unwired.isEmpty {
            base = Text("Toutes les voies sont branchées.")
        } else {
            let list = unwired.map(String.init).joined(separator: ", ")
            let one = unwired.count == 1
            base = direction == .send
                ? (one ? Text("Voie \(list) : aucune source branchée, l'émetteur enverra du silence.") : Text("Voies \(list) : aucune source branchée, l'émetteur enverra du silence."))
                : (one ? Text("Voie \(list) : aucune destination branchée.") : Text("Voies \(list) : aucune destination branchée."))
        }
        let summed = direction == .receive && !wiring.summedPorts(in: channels).isEmpty
        // A channel that the sender that is heard does not send stays silent.
        let beyond: [Int] = direction == .receive ? (model.controller.receiver.sender.map { s in channels.filter { $0 > s.channels } } ?? []) : []
        var text = base + (summed ? Text(" ") + Text("Un port qui reçoit plusieurs voies les additionne.") : Text(verbatim: ""))
        if !beyond.isEmpty, let sent = model.controller.receiver.sender?.channels {
            let list = ChannelList.format(beyond)
            text = text + Text(" ") + (beyond.count == 1
                ? Text("Voie \(list) : l'émetteur n'en envoie que \(sent), elle reste silencieuse.")
                : Text("Voies \(list) : l'émetteur n'en envoie que \(sent), elles restent silencieuses."))
        }
        return text.font(.callout).foregroundStyle(unwired.isEmpty && beyond.isEmpty ? Color.secondary : .orange)
    }
}
