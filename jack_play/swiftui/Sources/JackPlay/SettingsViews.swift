// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackPlayKit
import MatrixKit
import SwiftUI

/// A row of a settings group: title, an explanation under it, and the control on the right.
struct OptionRow<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// True while the setting cannot be changed (the program is started again for it, which would cut the sound): the
    /// control is dimmed, and a line under the text says how to change it.
    var locked: Bool
    /// What the line under the text says when the control is locked.
    var lockMessage: LocalizedStringKey
    @ViewBuilder var control: Control

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, locked: Bool = false,
         lockMessage: LocalizedStringKey = "Arrêtez la lecture (ou mettez-la en pause) pour changer ce réglage.",
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.locked = locked
        self.lockMessage = lockMessage
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if locked {
                    Label(lockMessage, systemImage: "lock.fill")
                        .font(.caption).fontWeight(.medium).foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }
                .disabled(locked)
                .opacity(locked ? 0.45 : 1)
                .help(locked ? Text(lockMessage) : Text(verbatim: ""))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.secondary).padding(.leading, 12)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().padding(.leading, 14) }
                        row
                    }
                }
            }
            .blockBackground()
        }
    }
}

/// A page of settings: scrolls, with the same margins everywhere.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(24).frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Outputs

/// A point of the matrix, lit in the accent of the application. On macOS 26 a Liquid Glass disc; before, the same look drawn flat.
struct AccentLED: View {
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
            dot
                .shadow(color: isOn ? accent.opacity(isHovered ? 0.8 : 0.55) : .clear, radius: isHovered ? 5 : 4)
                .scaleEffect(isHovered ? 1.2 : 1)
                .frame(width: 40, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(duration: 0.2, bounce: 0.35)) { isHovered = hovering } }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("activé") : Text("désactivé"))
    }

    /// Drawn flat on every system: Liquid Glass tinted with a teal reads as grey, and the lit point must show the accent.
    private var dot: some View {
        Circle().fill(fill).overlay(Circle().strokeBorder(outline, lineWidth: 1)).frame(width: 16, height: 16)
    }
}

/// Which input port of the graph each channel of the file feeds: one column per channel, the destinations by client in rows.
struct OutputsView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

    private static let nameWidth: CGFloat = 220, cellWidth: CGFloat = 40

    var body: some View {
        let player = model.player
        if let file = player.file {
            SettingsPage {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sorties").font(.title2).fontWeight(.semibold)
                    Text("Chaque voie du fichier est reliée aux ports JACK de votre choix. Les branchements sont mémorisés pour chaque fichier.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text("Fichier : \(file.url.lastPathComponent) · \(file.info.channels) voies").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Vers les premières sorties") { player.presetFirstOutputs() }
                    Button("Mono sur gauche et droite") { monoOnBothSides() }.disabled(file.info.channels != 1)
                    Button("Effacer") { player.setRouting(.empty(channels: file.info.channels)) }
                }
                if model.graph.destinations.isEmpty {
                    Text("Aucune entrée audio dans le graphe JACK.").foregroundStyle(.secondary)
                } else {
                    matrix(file).frame(height: min(420, matrixHeight)).blockBackground()
                }
                hint(file)
                SettingsGroup("Branchement") {
                    OptionRow("Brancher automatiquement",
                              "À chaque lecture, les branchements mémorisés du fichier sont rétablis. La première fois, ses voies vont aux premières sorties du système.") {
                        Toggle("Brancher automatiquement", isOn: Binding(get: { player.autoConnect }, set: { model.set(autoConnect: $0) }))
                            .labelsHidden().toggleStyle(.switch).accentTint()
                    }
                }
            }
        } else {
            NoFileView()
        }
    }

    /// What the matrix needs to show everything: the header, a row for each client and for each port that is shown.
    private var matrixHeight: CGFloat {
        model.graph.destinations.reduce(CGFloat(40)) { $0 + 44 + (collapsed.contains($1.name) ? 0 : CGFloat($1.ports.count) * 31) }
    }

    private func monoOnBothSides() {
        let ports = model.graph.playbackPorts
        guard model.player.file?.info.channels == 1, !ports.isEmpty else { return }
        model.player.setRouting(ChannelRouting(channels: [Array(ports.prefix(2))]))
    }

    private func matrix(_ file: OpenFile) -> some View {
        let player = model.player
        let n = file.info.channels
        let width = Self.nameWidth + Self.cellWidth * CGFloat(n)
        return GeometryReader { geometry in
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Ports JACK de destination").font(.callout).foregroundStyle(.secondary)
                        .padding(.leading, 14).frame(width: Self.nameWidth, alignment: .leading)
                    ForEach(0..<n, id: \.self) { channel in
                        ChannelNumber(number: channel + 1, warns: player.routing.channels[channel].isEmpty).frame(width: Self.cellWidth)
                    }
                }
                .frame(width: width, height: 40, alignment: .leading)
                ForEach(model.graph.destinations) { client in
                    let open = !collapsed.contains(client.name)
                    Button {
                        if open { collapsed.insert(client.name) } else { collapsed.remove(client.name) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 0 : -90)).frame(width: 12)
                            BadgeView(client: client.name, isPlayback: client.isPlayback, size: 28, bundleID: client.bundleID)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: client.displayName).fontWeight(.semibold)
                                Text("\(client.ports.count) entrées").font(.caption).foregroundStyle(.secondary)
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
                                ForEach(0..<n, id: \.self) { channel in
                                    AccentLED(isOn: player.routing.contains(channel: channel, port: full)) {
                                        player.toggle(channel: channel, port: full)
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

    private func hint(_ file: OpenFile) -> some View {
        let player = model.player
        let n = file.info.channels, used = player.routing.connectedChannels
        let base: Text = used == n ? Text("Toutes les voies sont reliées. ") : Text("\(used) voies sur \(n) reliées : les autres restent sans sortie. ")
        let sum: Text = player.summedPorts.isEmpty ? Text(verbatim: "") : Text("Un port qui reçoit plusieurs voies les additionne.")
        return (base + sum).font(.callout).foregroundStyle(used < n ? Color.orange : .secondary)
    }
}

// MARK: Loop and transport

struct LoopView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        SettingsPage {
            Text("Boucle et transport").font(.title2).fontWeight(.semibold)
            SettingsGroup("Boucle") {
                OptionRow("Répéter le fichier", "Le fichier recommence sans interruption.", locked: player.mode == .followTransport,
                          lockMessage: "Sans effet avec le transport JACK : le transport décide. Passez en mode Indépendant pour répéter.") {
                    Toggle("Répéter le fichier", isOn: Binding(get: { player.settings.loop }, set: { model.set(loop: $0) }))
                        .labelsHidden().toggleStyle(.switch).accentTint()
                }
            }
            SettingsGroup("Transport") {
                OptionRow("Mode", "Indépendant : le fichier se lit seul. Transport JACK : il démarre, s'arrête et se déplace avec le transport partagé par les autres clients.", locked: player.isPlaying) {
                    Picker("Mode", selection: Binding(get: { player.mode }, set: { model.set(mode: $0) })) {
                        Text("Indépendant").tag(PlayerCommand.Mode.independent)
                        Text("Transport JACK").tag(PlayerCommand.Mode.followTransport)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize().accentTint()
                }
                if player.mode == .followTransport {
                    OptionRow("Commander le transport", "Les boutons de la fenêtre démarrent, arrêtent et déplacent le transport. Désactivé, la fenêtre ne fait que suivre.") {
                        Toggle("Commander le transport", isOn: Binding(get: { player.commandsTransport }, set: { model.set(commandsTransport: $0) }))
                            .labelsHidden().toggleStyle(.switch).accentTint()
                    }
                }
            }
        }
    }
}

// MARK: Advanced

struct AdvancedView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    private static let converterNames: [Int: LocalizedStringKey] = [
        0: "Meilleure qualité", 1: "Qualité moyenne", 2: "Plus rapide", 3: "Maintien d'ordre zéro", 4: "Linéaire",
    ]

    var body: some View {
        let player = model.player
        SettingsPage {
            Text("Avancé").font(.title2).fontWeight(.semibold)
            SettingsGroup("Lecture") {
                OptionRow("Rééchantillonnage", "Utilisé quand la fréquence du fichier diffère de celle du serveur JACK.", locked: player.isPlaying) {
                    Picker("Rééchantillonnage", selection: Binding(get: { player.settings.converter }, set: { model.set(converter: $0) })) {
                        ForEach(PlayerSettings.converters, id: \.self) { Text(Self.converterNames[$0] ?? "?").tag($0) }
                    }
                    .labelsHidden().frame(width: 220, alignment: .trailing)
                }
                OptionRow("Tampon de lecture", "Plus il est grand, plus la lecture résiste aux disques lents, au prix d'un départ plus long. Le programme le relève seul s'il est trop petit pour la période du serveur JACK.", locked: player.isPlaying) {
                    Picker("Tampon de lecture", selection: Binding(get: { player.settings.bufferFrames }, set: { model.set(bufferFrames: $0) })) {
                        ForEach(PlayerSettings.bufferSizes, id: \.self) { Text("\($0) trames").tag($0) }
                    }
                    .labelsHidden().frame(width: 220, alignment: .trailing)
                }
            }
            SettingsGroup("JACK") {
                OptionRow("Nom du client", "Nom du lecteur dans le graphe JACK. JACK le complète si un autre client le porte déjà.", locked: player.isPlaying) {
                    TextField("Nom du client", text: $name)
                        .labelsHidden().frame(width: 200)
                        .onSubmit { model.set(clientName: name) }
                }
            }
        }
        .onAppear { name = player.settings.clientName }
        .onDisappear { if name != player.settings.clientName { model.set(clientName: name) } }
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
