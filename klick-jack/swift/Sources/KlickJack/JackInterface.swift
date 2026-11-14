// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).

import SwiftUI
import MatrixKit
import AppearanceKit
import KlickKit
import KlickUI

/// What the window shows of the JACK backend: its group on the page "Sortie" (the output port, the connection at start, what the
/// server announces, the list of the ports to connect to) and its part of the menu of the pill.
public struct JackInterface: BackendInterface {
    public let backendID = "jack"

    public init() {}

    public func stateDetail() -> Text? {
        Text("JACK : Klick joue dans le serveur JACK ; ses connexions se font ci-dessous ou dans un patchbay.")
    }

    public func outputSections(model: AppModel) -> AnyView { AnyView(JackSections()) }

    public func pillMenu(model: AppModel, close: @escaping () -> Void) -> AnyView { AnyView(JackPillMenu(close: close)) }
}

private struct JackSections: View {
    @Environment(AppModel.self) private var model

    private var jack: JackBackend? { model.backend as? JackBackend }
    @State private var showsAdvanced = false

    var body: some View {
        GroupTitle("JACK")
        VStack(spacing: 0) {
            OutputRow(title: "Client", detail: Text("Le nom de la sortie de Klick dans le serveur JACK.")) {
                Text(verbatim: jack?.portName ?? "").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            OutputRow(title: "Connexion automatique", detail: Text("Relie la sortie aux deux premières sorties du matériel quand le moteur démarre.")) {
                Toggle("", isOn: Binding(get: { JackBackend.autoconnects(model.settings) }, set: { jack?.setAutoconnect($0, model: model) }))
                    .labelsHidden().toggleStyle(.switch).accentTint()
            }
            Divider()
            OutputRow(title: "Fréquence d'échantillonnage", detail: Text("Celle du serveur JACK : Klick joue à ce rythme, sans conversion.")) {
                Text(verbatim: kHz(Double(model.player.sampleRate)))
            }
            Divider()
            OutputRow(title: "Latence annoncée", detail: Text("Ce que JACK annonce pour la sortie, une fois reliée : les voyants en tiennent compte.")) {
                Text(verbatim: "\(Int(model.output.latencyMilliseconds.rounded())) ms")
            }
            Divider()
            OutputRow(title: "Tampon", detail: Text("Taille des blocs du serveur JACK : plus elle est petite, moins il y a de retard.")) {
                Text("\(model.output.bufferFrames) échantillons")
            }
        }
        .groupBox()

        GroupTitle("Connexions")
        PortList()
            .groupBox()

        // Rarely wanted, and not for a first try: folded away at the bottom of the page.
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(spacing: 0) {
                OutputRow(title: "Suivre le transport JACK", detail: Text("Le métronome (ou la carte de tempo) attend le transport JACK, joue tant qu'il roule et s'arrête avec lui : le bouton de départ n'est plus nécessaire. Le métronome repart de son premier temps à chaque démarrage ; la carte joue à la position du transport. Sans décompte.")) {
                    Toggle("", isOn: Binding(get: { JackBackend.followsTransport(model.settings) }, set: { jack?.setFollowsTransport($0, model: model) }))
                        .labelsHidden().toggleStyle(.switch).accentTint()
                }
                Divider()
                OutputRow(title: "Être maître de timebase", detail: Text("Klick donne aux autres clients JACK le tempo, la mesure et la position en mesures et temps (comme klick), et prend la place du maître actuel. Sans cela, si un autre client est maître, le métronome simple prend son tempo et sa mesure.")) {
                    Toggle("", isOn: Binding(get: { JackBackend.isTimebaseMaster(model.settings) }, set: { jack?.setTimebaseMaster($0, model: model) }))
                        .labelsHidden().toggleStyle(.switch).accentTint()
                }
            }
            .groupBox()
            .padding(.top, 6)
        } label: {
            Text("Options avancées").font(.headline)
        }
        .padding(.top, 10)
        .onAppear { showsAdvanced = JackBackend.followsTransport(model.settings) || JackBackend.isTimebaseMaster(model.settings) }   // an option that is on is not hidden
    }

    private func kHz(_ rate: Double) -> String {
        rate > 0 ? (rate / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz" : "—"
    }
}

/// The input ports of the server, by client; a box checked is a port the output of Klick is connected to. One output, so a list and not a
/// matrix; the client badges (the real icon of an application when it is known, the loudspeaker of the hardware as in JackMate) are those
/// of the matrix of the other tools.
private struct PortList: View {
    @Environment(AppModel.self) private var model
    @State private var failure: String?

    private var groups: [JackClientPorts] { JackClientPorts.grouped((model.backend as? JackBackend)?.ports ?? []) }
    private var bundles: [String: String] { (model.backend as? JackBackend)?.bundles ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reliez la sortie de Klick aux ports de votre choix.")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 10).padding(.bottom, 4)
            if groups.isEmpty {
                Text("Aucun port d'entrée dans le serveur JACK.").foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { Divider() }
                HStack(spacing: 8) {
                    BadgeView(client: group.name, isPlayback: group.isPhysical, isJackMoebiusMaster: group.name == JackBackend.jackMoebiusClient, size: 22,
                              bundleID: bundles[group.name])
                    Text(verbatim: group.name).fontWeight(.medium)
                    Spacer()
                }
                .padding(.top, 8)
                // A check box per port, its name as the label: the name and the box are one control, close together; the box in the colour of the application.
                ForEach(group.ports) { port in
                    Toggle(isOn: Binding(get: { port.isConnected }, set: { _ in toggle(port) })) {
                        Text(verbatim: port.shortName).font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    .accentTint()
                    .padding(.leading, 30)
                    .padding(.vertical, 3)
                }
            }
            if let failure {
                Text(verbatim: failure).font(.caption).foregroundStyle(Color.alert).padding(.vertical, 6)
            }
        }
        .padding(.bottom, 8)
    }

    private func toggle(_ port: JackPort) {
        guard let jack = model.backend as? JackBackend else { return }
        failure = jack.setConnected(port.name, !port.isConnected, player: model.player)
    }
}

/// What the pill opens for JACK: the server, the rate and the latency, and the way to the page "Sortie".
private struct JackPillMenu: View {
    let close: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.output.name).font(.caption).fontWeight(.medium)
                Text(verbatim: "JACK · \((Double(model.player.sampleRate) / 1000).formatted(.number.precision(.fractionLength(0...1)))) kHz · \(Int(model.output.latencyMilliseconds.rounded())) ms")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.bottom, 4)
            PillRow(title: Text("Réglages de la sortie…"), close: close) { model.show(.output) }
        }
    }
}
