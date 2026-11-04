// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

/// The matrix of sources: one column per channel of the file, one row per JACK output. A lit dot
/// means the output feeds the channel; several in a column are added by JACK. It is the page of the
/// channels; every click changes the settings at once.
struct SourcesMatrix: View {
    @Environment(RecorderModel.self) private var model
    @State private var collapsed: Set<String> = []
    /// The sources of the settings, as the matrix edits them.
    private var draft: SourceAssignment {
        get { SourceAssignment(model.settings.sources, channels: model.settings.channels) }
        nonmutating set { model.settings.sources = newValue.perChannel }
    }
    /// Height of the footer, which floats over the bottom of the card.
    @State private var footerHeight: CGFloat = 0
    /// The clients whose input ports are listed too (jack_capture can also take what feeds an input).
    @State private var showInputs: Set<String> = []
    /// Where the dots are scrolled to: the heads follow x, the names follow y. A reference, read only by the
    /// `ScrollFollower`s, so that scrolling does not rebuild the whole sheet.
    @State private var scroll = MatrixScroll()
    /// The point under the pointer, which lights its row (name, client) and its column (number, badges).
    @State private var hover = MatrixHover()

    private let minColumnWidth: CGFloat = 52

    private var availablePorts: Set<String> {
        Set(graph.clients.flatMap { client in (client.ports + client.inputs).map { client.fullName(of: $0) } })
    }

    /// The chosen ports that are not in the graph any more. They stay listed, greyed, as long as a channel uses
    /// them, so that they can be unchosen; the last point put out, they are gone.
    private var absentChosenPorts: [String] {
        guard graph.isConnected else { return [] }
        let available = availablePorts
        return Set(draft.perChannel.flatMap { $0 }).filter { !available.contains($0) }.sorted()
    }

    /// The clients of the graph, plus the absent chosen ports (in their client when it is there, in a client
    /// of their own, marked absent, when it is not).
    private var shownClients: [JackSourceClient] {
        // An application seen before keeps its icon from the first image, before the daemon has answered.
        var clients = graph.clients.map { client -> JackSourceClient in
            var client = client
            if client.bundleID == nil { client.bundleID = model.settings.knownBundles[client.name] }
            return client
        }
        for full in absentChosenPorts {
            guard let colon = full.firstIndex(of: ":") else { continue }
            let name = String(full[..<colon]), port = String(full[full.index(after: colon)...])
            if let i = clients.firstIndex(where: { $0.name == name }) {
                clients[i].ports.append(port)
            } else {
                var ghost = JackSourceClient(name: name, ports: [port], isCapture: name == "system", isAbsent: true)
                ghost.bundleID = model.settings.knownBundles[name]   // the icon of an application seen before
                clients.append(ghost)
            }
        }
        return clients
    }

    /// Width of one channel column: the minimum, or wider for all of them when the recorder's name,
    /// which sits above the channels, needs more room than the columns together.
    private var columnWidth: CGFloat {
        let nameWidth = 2 + TextWidth.title(model.settings.jackClientName) + 12
        return max(minColumnWidth, (nameWidth / CGFloat(max(draft.channelCount, 1))).rounded(.up))
    }

    /// Width of the column of names: the longest client title or port name (the title has a chevron, a
    /// 30 pt badge and a bold name; the port is right-justified).
    private var portWidth: CGFloat {
        let titles = shownClients.map { 104 + TextWidth.title($0.displayName) }
        let ports = shownClients.flatMap(\.ports).map { 48 + CGFloat($0.count) * 7.2 }
        return min(max((titles + ports).max() ?? 0, 140), 340)
    }
    private let rowHeight: CGFloat = 30

    #if DEBUG
    private func debugFill() {
        if ProcessInfo.processInfo.environment["JACKCAPTURE_SOURCES"] == "collapse" {
            collapsed = Set(graph.clients.dropFirst().map(\.name))   // all but the first client
            for client in graph.clients.dropFirst() {
                for (i, port) in client.ports.prefix(3).enumerated() {
                    draft.toggle(port: client.fullName(of: port), channel: i == 2 ? 1 : 0)   // 2 ports in channel 1, 1 in channel 2
                }
            }
            return
        }
        if ProcessInfo.processInfo.environment["JACKCAPTURE_SOURCES"] == "inputs" {
            showInputs = Set(graph.clients.map(\.name))
            if let c = graph.clients.first(where: { !$0.inputs.isEmpty }), let p = c.inputs.first {
                draft.toggle(port: c.fullName(of: p), channel: 1)
            }
            draft.toggle(port: "system:capture_1", channel: 0)
            return
        }
        if let n = ProcessInfo.processInfo.environment["JACKCAPTURE_CH"].flatMap(Int.init) { model.settings.setChannels(n) }
        guard ProcessInfo.processInfo.environment["JACKCAPTURE_SOURCES"] == "fill" else { return }
        draft.fill(with: graph.systemInputs)
        if let metro = graph.clients.first(where: { !$0.isCapture })?.ports.first {
            draft.toggle(port: "\(graph.clients.first(where: { !$0.isCapture })!.name):\(metro)", channel: 0)
        }
    }
    #endif

    private var graph: JackGraph { model.graph }
    private var maxChannels: Int { model.settings.format.maxChannels }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chaque colonne est une voie du fichier. Le point allumé indique la sortie JACK qui l'alimente. Seuls les ports audio sont proposés : Jack Capture n'enregistre pas le MIDI.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            HStack(spacing: 8) {
                Button("Tout effacer") { draft.clear() }.buttonStyle(.bordered).fieldOutline()
                Spacer()
                // A check box here: a switch next to the matrix upsets the layout of the whole window.
                Toggle("Connecter automatiquement", isOn: Binding(get: { model.settings.autoConnect }, set: { model.settings.autoConnect = $0 }))
                    .toggleStyle(.checkbox)
                    .disabled(model.phase.isLocked)
                    .help("Relie les voies aux sources choisies au lancement. Désactivé, les voies restent à relier dans le patchbay.")
                Button { graph.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).fieldOutline()
                    .help("Actualiser le graphe JACK")
            }
            .padding(.horizontal, 24).padding(.bottom, 10)

            // The card takes the height left under the fixed header. The footer floats over its bottom, fading in:
            // when there are more rows than room, they pass under it and invite to scroll.
            // The matrix is laid out in the background: what it measures must not give the page a height of its own.
            ZStack(alignment: .bottom) {
                Color.clear
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    let size = CGSize(width: max(proxy.size.width - 48, 0), height: proxy.size.height)
                    let overflow = cardHeight + footerHeight > size.height
                    matrix(in: size, bottomInset: overflow ? footerHeight : 0)
                        .disabled(model.phase.isLocked)
                        .frame(width: proxy.size.width, height: overflow ? proxy.size.height : max(proxy.size.height - footerHeight, 0))
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            }
        }
        .frame(minHeight: 320)
        .onAppear { revealChosenInputs() }
        .onChange(of: graph.clients) { revealChosenInputs() }
        #if DEBUG
        .task { try? await Task.sleep(for: .milliseconds(2500)); debugFill() }
        #endif
    }

    // MARK: Footer

    /// The note, the count and the buttons, over a background that goes from transparent at the top to the
    /// colour of the window at the bottom.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            hint
                .font(.callout)
                .padding(.horizontal, 24).padding(.top, 10)

            HStack {
                Text(verbatim: countText).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
        }
        .padding(.top, 56)   // the fade
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let bg = Color.windowFill
            LinearGradient(stops: [.init(color: bg.opacity(0), location: 0),
                                   .init(color: bg.opacity(0.9), location: 0.27),
                                   .init(color: bg, location: 0.34)],
                           startPoint: .top, endPoint: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
    }

    // MARK: Matrix

    /// One row of the matrix: the title of a client, one of its output ports, the check box that shows its
    /// input ports, or one of its input ports.
    private struct Entry: Identifiable {
        enum Kind { case title, output, option, input }
        let client: JackSourceClient
        let kind: Kind
        var port: String? = nil
        var isLast = false
        var id: String {
            switch kind {
            case .title: return client.name
            case .option: return client.name + "#inputs"
            case .output, .input: return client.fullName(of: port ?? "")
            }
        }
        var isTitle: Bool { kind == .title }
        var height: CGFloat { isTitle ? ClientHeader.height : 30 }
    }

    /// The visible rows, in order: for each client its title and, if open, its ports. Identified by the full
    /// name, since two clients may have ports of the same name.
    private var entries: [Entry] {
        var all = shownClients.flatMap { client -> [Entry] in
            var rows = [Entry(client: client, kind: .title)]
            guard !collapsed.contains(client.name) else { return rows }
            rows += client.ports.map { Entry(client: client, kind: .output, port: $0) }
            if !client.inputs.isEmpty {
                rows.append(Entry(client: client, kind: .option))
                if showInputs.contains(client.name) {
                    rows += client.inputs.map { Entry(client: client, kind: .input, port: $0) }
                }
            }
            return rows
        }
        if !all.isEmpty { all[all.count - 1].isLast = true }
        return all
    }

    private func accent(of client: JackSourceClient) -> Color {
        // The main colour of the application icon when there is one, else the colour of the name.
        if let id = client.bundleID, let rgb = AppIcons.accent(forBundleID: id) { return rgb.color }
        return BadgeStyle(client: client.name, kind: client.isCapture ? .capture : .client).bottom.color
    }

    private func showInputsBinding(_ client: JackSourceClient) -> Binding<Bool> {
        Binding(get: { showInputs.contains(client.name) }, set: { on in
            if on { showInputs.insert(client.name) } else { showInputs.remove(client.name) }
        })
    }

    /// A client whose input port is already chosen shows its inputs, so that the choice is visible.
    private func revealChosenInputs() {
        for client in graph.clients where !client.inputs.isEmpty {
            let chosen = client.inputs.contains { port in
                draft.perChannel.contains { $0.contains(client.fullName(of: port)) }
            }
            if chosen { showInputs.insert(client.name) }
        }
    }

    private func toggleCollapsed(_ client: JackSourceClient) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if collapsed.contains(client.name) { collapsed.remove(client.name) } else { collapsed.insert(client.name) }
        }
    }

    /// The card is four regions, as the frozen panes of a spreadsheet: the corner (fixed), the channel
    /// heads (they follow the horizontal scroll), the names (they follow the vertical scroll) and the dots,
    /// which scroll both ways and report where they are. The names therefore never leave the screen,
    /// however many channels there are.
    @ViewBuilder private func matrix(in available: CGSize, bottomInset: CGFloat) -> some View {
        if !graph.isConnected {
            placeholder("JACK n'est pas démarré. Les sources apparaîtront dès qu'il le sera.")
        } else if shownClients.isEmpty {
            placeholder("Aucune sortie audio dans le graphe JACK.")
        } else {
            // The card is as big as its content, and no bigger than the room there is. Past that, the dots
            // scroll and the heads and the names follow.
            let height = min(cardHeight + bottomInset, available.height)
            let width = min(cardWidth, available.width)
            let viewportWidth = max(min(channelsWidth, width - portWidth - 2), 0)
            let bodyHeight = max(height - Self.bandHeight - Self.headerHeight, 0)
            VStack(spacing: 0) {
                HStack(spacing: 0) { corner; topRegion(width: viewportWidth) }
                HStack(spacing: 0) {
                    leftRegion(height: bodyHeight, bottomInset: bottomInset)
                    bodyRegion(width: viewportWidth, height: bodyHeight, bottomInset: bottomInset)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            // An absent client whose last point goes out fades away, and the card closes over the gap.
            .animation(.easeInOut(duration: 0.3), value: absentChosenPorts)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius))
            .blockBackground(cornerRadius: Self.cardRadius)
            // A fine outline of its own: the glass loses its edge when the window is not in front, this one stays.
            .overlay { RoundedRectangle(cornerRadius: Self.cardRadius).strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5) }
        }
    }

    private static let headerHeight: CGFloat = 80
    private static let poof = AnyTransition.opacity.combined(with: .scale(scale: 0.8))
    /// Corner radius of the card of the matrix (16 for rounded corners).
    private static let cardRadius: CGFloat = 0
    private static let bandHeight: CGFloat = 46
    private static let strongRule = Color.primary.opacity(0.22)

    /// Width of the channels together: every column has the same width.
    private var channelsWidth: CGFloat { columnWidth * CGFloat(draft.channelCount) }

    private var cardWidth: CGFloat { portWidth + channelsWidth + 2 }

    /// Height of the whole card: the recorder band, the channel heads and the rows (all of fixed height).
    private var cardHeight: CGFloat {
        let fixed = Self.bandHeight + Self.headerHeight
        return fixed + entries.reduce(0) { $0 + $1.height } + 1
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    // MARK: Corner and heads

    /// The recorder in the JACK graph, which the channels feed: its icon closes the column of names, right
    /// against the first channel.
    private var corner: some View {
        let name = model.settings.jackClientName
        return VStack(spacing: 0) {
            BadgeView(client: name, size: 26)
                .padding(.trailing, 12)
                .frame(width: portWidth, height: Self.bandHeight, alignment: .trailing)
                .overlay(alignment: .bottom) { Rectangle().fill(Self.strongRule).frame(height: 1) }
            Color.clear.frame(width: portWidth, height: Self.headerHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Self.strongRule).frame(height: 1) }
        }
        .frame(width: portWidth)
    }

    /// The recorder band and the channel heads. They follow the horizontal scroll; the recorder's name stays
    /// at the start of the channels.
    private func topRegion(width: CGFloat) -> some View {
        let name = model.settings.jackClientName
        return ZStack(alignment: .topLeading) {
            ScrollFollower(scroll: scroll, axis: .horizontal) {
              VStack(spacing: 0) {
                Color.clear.frame(width: channelsWidth, height: Self.bandHeight)
                    .overlay(alignment: .bottom) { Rectangle().fill(Self.strongRule).frame(height: 1) }
                    // The accent of the recorder, along the bottom of the band, over the channels only.
                    .overlay(alignment: .bottomLeading) {
                        Rectangle().fill(BadgeStyle(client: name).bottom.color).frame(width: channelsWidth, height: 3)
                    }
                headerCells
              }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(verbatim: "\(draft.channelCount)in")
                    .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.leading, 2)
            .frame(height: Self.bandHeight, alignment: .center)
        }
        .frame(width: width, height: Self.bandHeight + Self.headerHeight, alignment: .topLeading)
        .clipped()
    }

    private var headerCells: some View {
        HStack(spacing: 0) {
            ForEach(0..<draft.channelCount, id: \.self) { c in
                let sources = draft.perChannel[c]
                VStack(spacing: 12) {
                    HoverReader(hover) { h in
                        let lit = h.column == c
                        // A disc for one or two digits; from three it grows into a pill and the figures get a little smaller.
                        Text("\(c + 1)").font(.system(size: c + 1 >= 100 ? 10 : 11, weight: .semibold)).monospacedDigit()
                            .padding(.horizontal, c + 1 >= 100 ? 5 : 0)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(sources.isEmpty ? Color.alert.opacity(lit ? 0.7 : 0.35)
                                                        : Color.primary.opacity(lit ? 0.38 : 0.12), in: Capsule())
                            .scaleEffect(lit ? 1.18 : 1)
                            .animation(.easeOut(duration: 0.15), value: lit)
                    }
                    HoverReader(hover) { h in
                        Group {
                            if sources.isEmpty {
                                RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .frame(width: 24, height: 24)
                            } else {
                                BadgeStack(clients: sources.map { clientInfo($0) }, size: 24)
                            }
                        }
                        .scaleEffect(h.column == c ? 1.15 : 1)
                        .animation(.easeOut(duration: 0.15), value: h.column == c)
                    }
                }
                .background { HoverReader(hover) { h in Color.primary.opacity(h.column == c ? 0.07 : 0).animation(.easeOut(duration: 0.15), value: h.column == c) } }
                .padding(.vertical, 10)
                .frame(width: columnWidth)
                .frame(maxHeight: .infinity)
                .columnRule()
                .help(Text(verbatim: sources.isEmpty ? "—" : sources.joined(separator: " + ")))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Voie \(c + 1)"))
            }
        }
        .frame(width: channelsWidth, height: Self.headerHeight, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Self.strongRule).frame(height: 1) }
    }

    // MARK: Names

    /// The column of names. It follows the vertical scroll and never the horizontal one.
    private func leftRegion(height: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollFollower(scroll: scroll, axis: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in nameRow(entry).transition(Self.poof) }
            }
            .padding(.bottom, bottomInset)
            .frame(width: portWidth, alignment: .topLeading)
        }
        .frame(width: portWidth, height: height, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder private func nameRow(_ entry: Entry) -> some View {
        let client = entry.client
        Group {
            switch entry.kind {
            case .output, .input:
                let port = entry.port ?? ""
                let full = client.fullName(of: port)
                HStack(spacing: 6) {
                    if entry.kind == .input {
                        Image(systemName: "arrow.down.to.line").font(.caption).foregroundStyle(.secondary)
                            .help("Port d'entrée : jack_capture prend ce qui lui est relié.")
                    } else if graph.heardPorts.contains(full) {
                        Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(.secondary)
                            .help("Connecté aux sorties système")
                    }
                    Text(verbatim: port).lineLimit(1).truncationMode(.head)
                        .foregroundStyle(entry.kind == .input ? Color.secondary : Color.primary)
                }
                .opacity(availablePorts.contains(full) ? 1 : 0.5)
                .help(availablePorts.contains(full) ? "" : String(localized: "Ce port n'est plus dans le graphe JACK."))
                // Right-justified, next to the dots of the first column.
                .padding(.leading, 30).padding(.trailing, 16)
                .frame(width: portWidth, height: entry.height, alignment: .trailing)
                .overlay(alignment: .top) { Divider().opacity(0.5) }
            case .option:
                Toggle(isOn: showInputsBinding(client)) {
                    Text("Afficher aussi les entrées").font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Afficher aussi les ports d'entrée de ce client : jack_capture prend ce qui leur est relié au lancement.")
                .padding(.trailing, 16)
                .frame(width: portWidth, height: entry.height, alignment: .trailing)
                .overlay(alignment: .top) { Divider().opacity(0.5) }
            case .title:
                ClientHeader(client: client, isCollapsed: collapsed.contains(client.name), width: portWidth,
                             shownInputs: showInputs.contains(client.name) ? client.inputs.count : 0) {
                    toggleCollapsed(client)
                }
                // What the interface knows of the client: the application it stands for, if JackMoebius says so.
                .help(client.bundleID.map { String(localized: "Application : \($0)") }
                      ?? (client.isCapture ? "" : String(localized: "Aucune application associée à ce client JACK.")))
                .overlay(alignment: .top) { Rectangle().fill(Self.strongRule).frame(height: 1) }
            }
        }
        // The row under the pointer, or the client it belongs to, is lit.
        .background {
            HoverReader(hover) { h in
                let lit = entry.isTitle ? h.client == client.name : h.row == entry.id
                Color.primary.opacity(lit ? (entry.isTitle ? 0.06 : 0.11) : 0).animation(.easeOut(duration: 0.15), value: lit)
            }
        }
        // The accent bar of the client closes the column of names, on its right edge, against the first channel.
        .overlay(alignment: .trailing) { Rectangle().fill(accent(of: client)).frame(width: 3) }
        .overlay(alignment: .bottom) {
            if entry.isLast { Rectangle().fill(Self.strongRule).frame(height: 1) }
        }
    }

    // MARK: Dots

    private func bodyRegion(width: CGFloat, height: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in dotRow(entry).transition(Self.poof) }
            }
            .padding(.bottom, bottomInset)
            .frame(width: channelsWidth, alignment: .leading)
            .overlay(alignment: .topLeading) { columnRules }
            .overlay(alignment: .topLeading) { hoverVeil }
            // The names and the heads are not scroll views: the wheel over them is handed to the dots.
            .background(WheelBridge(namesWidth: portWidth, headsHeight: Self.bandHeight + Self.headerHeight))
        }
        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in scroll.move(to: new) }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: height)
    }

    @ViewBuilder private func dotRow(_ entry: Entry) -> some View {
        let client = entry.client
        Group {
            if entry.kind == .option {
                Color.clear.frame(width: channelsWidth, height: entry.height)
                    .overlay(alignment: .top) { Divider().opacity(0.5) }
            } else if let port = entry.port {
                let full = client.fullName(of: port)
                HStack(spacing: 0) {
                    ForEach(0..<draft.channelCount, id: \.self) { c in
                        LED(isOn: draft.isOn(port: full, channel: c), onHover: { inside in
                            if inside { hover.set(row: entry.id, client: client.name, column: c) }
                            else { hover.clear(row: entry.id, column: c) }
                        }) { draft.toggle(port: full, channel: c) }
                            .frame(width: columnWidth, height: entry.height)
                            .accessibilityLabel(Text(verbatim: "\(String(localized: "Voie \(c + 1)")), \(client.displayName), \(port)"))
                    }
                }
                .overlay(alignment: .top) { Divider().opacity(0.5) }
            } else {
                // A closed client still says what it feeds: in the cell of each channel, the number of its
                // ports lit for that channel, in the colour of the points.
                HStack(spacing: 0) {
                    ForEach(0..<draft.channelCount, id: \.self) { c in
                        let n = collapsed.contains(client.name)
                            ? (client.ports + client.inputs).filter { draft.isOn(port: client.fullName(of: $0), channel: c) }.count : 0
                        Text(n > 0 ? "\(n)" : "")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.ledOn)
                            .shadow(color: Color.ledOn.opacity(0.55), radius: 4)
                            .frame(width: columnWidth, height: entry.height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleCollapsed(client) }
                .overlay(alignment: .top) { Rectangle().fill(Self.strongRule).frame(height: 1) }
            }
        }
        .overlay(alignment: .bottom) {
            if entry.isLast { Rectangle().fill(Self.strongRule).frame(height: 1) }
        }
    }

    /// A faint veil over the row and the column of the point under the pointer.
    private var hoverVeil: some View {
        var rows: [String: (y: CGFloat, height: CGFloat)] = [:]
        var y: CGFloat = 0
        for entry in entries { rows[entry.id] = (y, entry.height); y += entry.height }
        let total = y, columnWidth = columnWidth, channelsWidth = channelsWidth
        return HoverReader(hover) { h in
            ZStack(alignment: .topLeading) {
                if let id = h.row, let row = rows[id] {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(width: channelsWidth, height: row.height).offset(y: row.y)
                }
                if let c = h.column, c < draftChannelCountForVeil {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(width: columnWidth, height: total).offset(x: CGFloat(c) * columnWidth)
                }
            }
            .animation(.easeOut(duration: 0.12), value: h.row)
            .animation(.easeOut(duration: 0.12), value: h.column)
            .allowsHitTesting(false)
        }
    }

    private var draftChannelCountForVeil: Int { draft.channelCount }

    /// One hairline on the left of each channel column, over the whole height of the rows.
    private var columnRules: some View {
        HStack(spacing: 0) {
            ForEach(0..<draft.channelCount, id: \.self) { _ in
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5)
                    .frame(width: columnWidth, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func clientInfo(_ full: String) -> (name: String, isCapture: Bool, bundleID: String?) {
        let name = full.split(separator: ":", maxSplits: 1).first.map(String.init) ?? full
        let known = graph.clients.first { $0.name == name }
        return (name, known?.isCapture ?? (name == "system"), known?.bundleID ?? model.settings.knownBundles[name])
    }

    // MARK: Hint and counts

    @ViewBuilder private var hint: some View {
        let problems = model.sourceCheck.descriptions
        if !problems.isEmpty {
            // What would make a channel silent, one sentence per problem.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(problems, id: \.self) { Text($0) }
                Text("Les voies concernées seront enregistrées en silence.")
            }
            .foregroundStyle(Color.alert)
        } else if draft.usedCount > 0 && draft.usedCount < draft.channelCount {
            Text("Les voies sans source seront enregistrées en silence.").foregroundStyle(Color.alert)
        } else if hasChosenInput {
            Text("Un port d'entrée apporte ce qui lui est relié au lancement : les connexions faites ensuite ne sont pas suivies.")
                .foregroundStyle(.secondary)
        } else if draft.summedCount > 0 {
            let integer = !model.settings.format.isLossy && model.settings.depth != .float32
            Text(integer
                 ? "Les sources d'une même voie sont additionnées, sans réglage de niveau. En entiers, un dépassement de 0 dBFS écrête."
                 : "Les sources d'une même voie sont additionnées, sans réglage de niveau. En virgule flottante, un dépassement est conservé.")
                .foregroundStyle(integer ? Color.alert : .secondary)
        } else {
            Text("Plusieurs points allumés dans une colonne additionnent leurs sources. Une sortie peut aussi alimenter plusieurs voies.")
                .foregroundStyle(.secondary)
        }
    }

    private var hasChosenInput: Bool {
        let inputs = Set(graph.clients.flatMap { c in c.inputs.map { c.fullName(of: $0) } })
        return draft.perChannel.contains { $0.contains { inputs.contains($0) } }
    }

    private var countText: String {
        var s = String(localized: "Sources choisies : \(draft.usedCount) sur \(draft.channelCount).")
        if draft.summedCount > 0 {
            if s.hasSuffix(".") { s.removeLast() }
            s += " · " + String(localized: "additionnées : \(draft.summedCount)")
        }
        return s
    }

    // MARK: Actions
}

/// The title of a client in the matrix, as the section headers of Finder's list view: no filled bar,
/// a disclosure chevron, the badge and the name, a hairline underneath. Under the pointer only the
/// chevron brightens.
struct ClientHeader: View {
    let client: JackSourceClient
    let isCollapsed: Bool
    let width: CGFloat
    /// How many input ports are listed under the client (0: none, the count says "out" only).
    var shownInputs = 0
    let toggle: () -> Void
    static let height: CGFloat = 46
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 12)
                BadgeView(client: client.name, isCapture: client.isCapture, size: 30, bundleID: client.bundleID)
                    .opacity(client.isAbsent ? 0.45 : 1)
                // Same layout as the boxes of the JackMate patchbay: the name, then what the client offers.
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: client.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if client.isAbsent {
                        Text("absent").font(.caption).foregroundStyle(Color.alert)
                    } else {
                        Text(verbatim: "\(client.ports.count)out" + (shownInputs > 0 ? " · \(shownInputs)in" : ""))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: ClientHeader.height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isCollapsed ? Text("replié") : Text("déplié"))
    }
}
