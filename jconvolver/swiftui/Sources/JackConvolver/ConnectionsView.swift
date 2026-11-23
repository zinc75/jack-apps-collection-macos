// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackBridge
import JConvolverKit
import MatrixKit
import SwiftUI

/// The channels of jconvolver connected to the ports of the other JACK clients. The columns are the channels of the program,
/// the rows are the ports of the other clients, grouped by client. A channel can have several ports: the configuration file
/// lists them, and jconvolver (with the 0004 patch) connects them all when it starts.
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

    private static let nameWidth: CGFloat = 230, cellWidth: CGFloat = 44

    var body: some View {
        if model.wiringSource == nil {
            SettingsPage {
                Text("Connexions").font(.title2).fontWeight(.semibold)
                Text("Aucune configuration ouverte.").foregroundStyle(.secondary)
            }
        } else {
            content
        }
    }

    private var side: PortSide { model.connectionSide }

    private var content: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connexions").font(.title2).fontWeight(.semibold)
                Text("Chaque voie de jconvolver se relie à des ports d'autres applications.").font(.callout).foregroundStyle(.secondary)
            }
            if model.isLocked, model.mode == .realTime {
                // The only thing that is changed while the engine runs: made in JACK at once, the file is not touched.
                Label("Moteur en marche : les branchements s'appliquent tout de suite à JACK, sans modifier le fichier de configuration. À l'arrêt, vous pourrez les y reporter.",
                      systemImage: "arrow.left.arrow.right")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            // The two ways are two tabs laid out as the system does (the tabs centred over a box), but drawn here: the tab view of
            // macOS keeps the accent of the system and ignores the one of the application.
            VStack(spacing: 0) {
                GlassTabs(selection: $model.connectionSide, items: [(.input, String(localized: "Entrées")), (.output, String(localized: "Sorties"))])
                    .padding(.top, 12).padding(.horizontal, 12)
                tab(side)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.jack.excludedClients = [model.ownClientName]; model.jack.refresh() }
        .onChange(of: model.ownClientName) { _, name in model.jack.excludedClients = [name] }
    }

    /// One way: what it is, the menu to start again, the matrix and what it says.
    private func tab(_ way: PortSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(way == .input ? "De JACK vers jconvolver" : "De jconvolver vers JACK").font(.callout).foregroundStyle(.secondary)
                InfoButton(text: "Une voie peut avoir plusieurs ports ; leurs signaux s'additionnent. Le fichier de configuration les écrit sur la ligne de la voie : le jconvolver livré avec cette application les connecte tous, une autre version ne connecte que le premier. Les connexions que vous faites ailleurs (patchbay) ne sont ni montrées ni modifiées ici.")
                Spacer()
                Menu("Réinitialiser") {
                    Button("Effacer tous les branchements") { model.clearWires(way) }
                    Button(way == .input ? "Revenir à l'entrée système" : "Revenir à la sortie système") { model.wireToSoundCard(way) }
                        .disabled((way == .input ? model.jack.capturePorts : model.jack.playbackPorts).isEmpty)
                }
                .fixedSize()
                .help("Efface les branchements, ou remet chaque voie sur le port du même numéro de la carte son.")
            }
            matrix.frame(maxHeight: .infinity).blockBackground()
            hint
        }
        .padding(16)
    }

    // MARK: The matrix

    private var channels: [Int] { Array(0..<((side == .input ? model.wiringSource?.inputCount : model.wiringSource?.outputCount) ?? 0)) }

    private var clients: [JackPortClient] { side == .input ? model.jack.sources : model.jack.destinations }

    /// Ports the file connects to that are not in the graph (the other application is not running, or JACK is not).
    private var absentPorts: [String] {
        let known = Set(clients.flatMap { c in c.ports.map { c.fullName(of: $0) } })
        let named = channels.flatMap { model.wiringSource?.connections(side, $0) ?? [] }
        return Array(Set(named).subtracting(known)).sorted()
    }

    private var matrix: some View {
        let width = Self.nameWidth + Self.cellWidth * CGFloat(channels.count)
        return GeometryReader { geometry in
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if !model.jack.isConnected {
                        Text("JACK n'est pas démarré : les ports des autres applications apparaîtront dès qu'il l'est.")
                            .font(.callout).foregroundStyle(.secondary).padding(14)
                    } else if clients.isEmpty {
                        Text(side == .input ? "Aucune sortie audio dans le graphe JACK." : "Aucune entrée audio dans le graphe JACK.")
                            .font(.callout).foregroundStyle(.secondary).padding(14)
                    }
                    ForEach(clients) { client in clientRows(client, width: width) }
                    if !absentPorts.isEmpty { absentRows(width: width) }
                } header: {
                    header(width: width)
                }
            }
            // At the top left, not centred in what is left of the block.
            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
        }
        }
    }

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(side == .input ? "Ports JACK de source" : "Ports JACK de destination").font(.callout).foregroundStyle(.secondary)
                .padding(.leading, 14).frame(width: Self.nameWidth, alignment: .leading)
            ForEach(channels, id: \.self) { index in
                let name = model.wiringSource?.portName(side, index) ?? ""
                VStack(spacing: 2) {
                    ChannelNumber(number: index + 1, warns: model.wiringSource?.connections(side, index).isEmpty ?? true)
                    Text(verbatim: name).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(name)
                }
                .frame(width: Self.cellWidth)
            }
        }
        .frame(width: width, height: 44, alignment: .leading)
        .background(Color.windowFill)
    }

    private func clientRows(_ client: JackPortClient, width: CGFloat) -> some View {
        let open = !collapsed.contains(client.name)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open { collapsed.insert(client.name) } else { collapsed.remove(client.name) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 0 : -90)).frame(width: 12)
                    BadgeView(client: client.name, isCapture: side == .input && client.isSystem, isPlayback: side == .output && client.isSystem,
                              isJackMoebiusMaster: client.isJackMoebiusMaster, size: 28, bundleID: client.bundleID)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: displayName(client)).fontWeight(.semibold)
                        Text(client.ports.count == 1 ? "1 port" : "\(client.ports.count) ports").font(.caption).foregroundStyle(.secondary)
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
                ForEach(client.ports, id: \.self) { port in portRow(name: port, full: client.fullName(of: port), width: width) }
            }
        }
    }

    private func absentRows(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Absents du graphe JACK").fontWeight(.semibold)
                    Text("Ports du fichier dont l'application ne tourne pas").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            ForEach(absentPorts, id: \.self) { full in portRow(name: full, full: full, width: width) }
        }
    }

    private func portRow(name: String, full: String, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider().frame(width: width)
            HStack(spacing: 0) {
                Text(verbatim: name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 30).frame(width: Self.nameWidth, alignment: .leading)
                ForEach(channels, id: \.self) { index in
                    WireLED(isOn: model.wiringSource?.connections(side, index).contains(full) ?? false) {
                        model.toggleWire(side, channel: index, port: full)
                    }
                }
            }
            .frame(width: width, height: 30, alignment: .leading)
        }
    }

    private func displayName(_ client: JackPortClient) -> String {
        guard client.isSystem else { return client.name }
        return side == .input ? "system (capture)" : "system (playback)"
    }

    // MARK: What it says

    private var hint: some View {
        let loose = model.unconnected(side)
        let list = loose.map(String.init).joined(separator: ", ")
        let base: Text
        if loose.isEmpty {
            base = Text("Toutes les voies sont branchées.")
        } else if side == .input {
            base = loose.count == 1 ? Text("Voie \(list) : aucune source branchée, l'entrée restera silencieuse.")
                                    : Text("Voies \(list) : aucune source branchée, les entrées resteront silencieuses.")
        } else {
            base = loose.count == 1 ? Text("Voie \(list) : aucune destination branchée.") : Text("Voies \(list) : aucune destination branchée.")
        }
        let summed = side == .output && !(model.wiringSource?.summedDestinations.isEmpty ?? true)
        let mixed = side == .input ? (model.wiringSource?.mixedInputs ?? []).map { $0 + 1 } : []
        var text = base + (summed ? Text(" ") + Text("Un port qui reçoit plusieurs sorties les additionne.") : Text(verbatim: ""))
        if !mixed.isEmpty {
            let list = mixed.map(String.init).joined(separator: ", ")
            text = text + Text(" ") + (mixed.count == 1 ? Text("Entrée \(list) : plusieurs sources, leurs signaux s'additionnent.")
                                                          : Text("Entrées \(list) : plusieurs sources, leurs signaux s'additionnent."))
        }
        return text.font(.callout).foregroundStyle(loose.isEmpty ? Color.secondary : .orange)
    }
}

/// A point of the matrix, lit in the accent of the application. Drawn flat on every system: Liquid Glass tinted with the accent
/// would read as grey, and the lit point must show the accent.
struct WireLED: View {
    let isOn: Bool
    let action: () -> Void
    @Environment(\.appAccentColor) private var accent
    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    private var fill: Color { isOn ? accent : (scheme == .dark ? .ledOffFill : Color(white: 0, opacity: 0.07)) }
    private var outline: Color {
        if isOn { return accent.opacity(isHovered ? 0.9 : 0.5) }
        let base = scheme == .dark ? Color.white : Color.black
        return base.opacity(isHovered ? 0.35 : (scheme == .dark ? 0.06 : 0.14))
    }

    var body: some View {
        Button(action: action) {
            Circle().fill(fill).overlay(Circle().strokeBorder(outline, lineWidth: 1)).frame(width: 16, height: 16)
                .shadow(color: isOn ? accent.opacity(isHovered ? 0.8 : 0.55) : .clear, radius: isHovered ? 5 : 4)
                .scaleEffect(isHovered ? 1.2 : 1)
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(duration: 0.2, bounce: 0.35)) { isHovered = hovering } }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("activé") : Text("désactivé"))
    }
}

/// The number of a channel, in a disc.
struct ChannelNumber: View {
    let number: Int
    var warns = false
    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .frame(width: 20, height: 20)
            .background(warns ? Color.orange.opacity(0.3) : Color.primary.opacity(0.1), in: Circle())
    }
}
