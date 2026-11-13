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
            OutputRow(title: "Latence annoncée", detail: Text("Ce que JACK annonce pour la sortie, une fois reliée : les lampes en tiennent compte.")) {
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
    }

    private func kHz(_ rate: Double) -> String {
        rate > 0 ? (rate / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz" : "—"
    }
}

/// The input ports of the server, by client; a point lit is a port the output of Klick is connected to. One output, so a list and not a
/// matrix; the client badges and the points are those of the matrix of the other tools.
private struct PortList: View {
    @Environment(AppModel.self) private var model
    @State private var failure: String?

    private var groups: [JackClientPorts] { JackClientPorts.grouped((model.backend as? JackBackend)?.ports ?? []) }

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
                    BadgeView(client: group.name, size: 22)
                    Text(verbatim: group.name).fontWeight(.medium)
                    Spacer()
                }
                .padding(.top, 8)
                ForEach(group.ports) { port in
                    HStack {
                        Text(verbatim: port.shortName).font(.callout).padding(.leading, 30)
                        Spacer()
                        LED(isOn: port.isConnected) { toggle(port) }
                    }
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
