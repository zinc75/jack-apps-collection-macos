// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackPlayKit
import MatrixKit
import MeterKit
import SwiftUI
import WaveformKit

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        if let file = model.player.file {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(file)
                    timePanel(file)
                    levelsPanel(file)
                    connectionsPanel(file)
                }
                .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 16)
            }
        } else {
            NoFileView()
        }
    }

    // MARK: File

    private func header(_ file: OpenFile) -> some View {
        let info = file.info
        let serverRate = model.graph.sampleRate.map(Double.init)
        let rate = Self.kHz(info.sampleRate)
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if model.playlist.playlist.count > 1, let place = model.playlist.playlist.current {
                    Text("Fichier \(place + 1) sur \(model.playlist.playlist.count)").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                }
                Text(verbatim: file.url.lastPathComponent)
                    .font(.system(size: 22, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Chip(text: Text(verbatim: "\(info.container) · \(info.encoding)"))
                    Chip(text: Text(Plural.channels(info.channels)))
                    if let serverRate, abs(serverRate - info.sampleRate) > 0.5 {
                        Chip(text: Text(verbatim: "\(rate) kHz → \(Self.kHz(serverRate)) kHz"), kind: .warn, symbol: "waveform.path")
                            .help("La fréquence du fichier diffère de celle de JACK : il est rééchantillonné.")
                    } else {
                        Chip(text: Text(verbatim: "\(rate) kHz"))
                    }
                    Chip(text: Text(verbatim: TimeFormat.clock(info.duration)))
                }
                nextLine
            }
            Spacer(minLength: 12)
            if model.playlist.playlist.count > 1 { Button("Voir la liste") { model.page = .playlist } }
            Button("Ouvrir…") { model.chooseFile() }
        }
    }

    /// The file that comes after this one.
    @ViewBuilder private var nextLine: some View {
        if model.player.mode == .independent, let next = model.playlist.nextFile {
            (Text("Ensuite : ") + Text(verbatim: next.lastPathComponent).fontWeight(.medium))
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private static func kHz(_ rate: Double) -> String { (rate / 1000).formatted(.number.precision(.fractionLength(0...1))) }

    // MARK: Time and waveform

    private func timePanel(_ file: OpenFile) -> some View {
        let player = model.player
        let wf = player.waveform
        let lane: CGFloat = file.info.channels > 8 ? 18 : file.info.channels > 2 ? 30 : 60
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: TimeFormat.clock(player.positionSeconds, tenths: true))
                        .font(.system(size: 56, weight: .ultraLight)).monospacedDigit().tracking(-1)
                    Text(verbatim: "/ \(TimeFormat.clock(player.duration))").font(.system(size: 15)).monospacedDigit().foregroundStyle(.secondary)
                    if model.playlist.repeatMode != .off, player.mode == .independent {
                        Chip(text: Text(model.playlist.repeatMode == .list ? "Répète la liste" : "Répète le fichier"), kind: .accent, symbol: "repeat").padding(.leading, 8)
                    }
                    Spacer()
                    Text(verbatim: "−" + TimeFormat.clock(max(player.duration - player.positionSeconds, 0)))
                        .font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: TimeRulerView.height)
                        ForEach(0..<file.info.channels, id: \.self) { channel in
                            ChannelNumber(number: channel + 1).frame(height: lane)
                        }
                    }
                    .frame(width: 30)
                    VStack(spacing: 0) {
                        TimeRulerView(duration: player.duration)
                        ZStack {
                            WaveformView(peaks: wf.finishedPeaks, channels: file.info.channels, position: player.fraction,
                                         laneHeight: lane, playedColor: accent, accessibilityLabel: "Forme d'onde",
                                         onSeek: { model.scrub(to: $0) })
                            if wf.state == .loading {
                                ProgressView(value: wf.progress).progressViewStyle(.linear).frame(width: 220).accentTint()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Levels and connections

    private func levelsPanel(_ file: OpenFile) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Niveaux de sortie (dBFS)").font(.headline)
                    .help("Niveau à la sortie de jack_play, indépendant des branchements.")
                MeterBars(meters: model.player.meters, channels: file.info.channels, scale: IECScale(), label: "Niveaux de sortie")
            }
        }
    }

    private func connectionsPanel(_ file: OpenFile) -> some View {
        let player = model.player
        let clients = player.routing.clients
        let silent = file.info.channels - player.routing.connectedChannels
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Branchements de ce fichier").font(.headline)
                    Spacer()
                    Button("Modifier…") { model.page = .outputs }
                }
                HStack(spacing: 6) {
                    ForEach(clients, id: \.self) { name in
                        let known = model.graph.destinations.first { $0.name == name }
                        HStack(spacing: 6) {
                            BadgeView(client: name, isPlayback: name == "system", isJackMoebiusMaster: known?.isJackMoebiusMaster ?? false,
                                      size: 16, bundleID: known?.bundleID)
                            Text(verbatim: name == "system" ? "system (playback)" : name)
                        }
                        .font(.caption).fontWeight(.medium)
                        .padding(.leading, 4).padding(.trailing, 9).frame(height: 24)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    if clients.isEmpty {
                        Chip(text: Text("Aucune sortie n'est connectée"), kind: .warn, symbol: "exclamationmark.triangle.fill")
                    } else if silent > 0 {
                        Chip(text: Text(Plural.silentChannels(silent)), kind: .warn, symbol: "exclamationmark.triangle.fill")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: Controls

/// The footer of every page while a file is open: where the transport is, the buttons, the command line.
struct ControlsBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let player = model.player
        HStack(spacing: 16) {
            transportState.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                Button { model.playlist.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 13)).frame(width: 42, height: 42) }
                    .buttonStyle(PressStyle()).glassCircle().help("Fichier précédent")
                    .disabled(!listPlays || model.playlist.playlist.current == nil)
                Button { player.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 14)).frame(width: 42, height: 42) }
                    .buttonStyle(PressStyle()).glassCircle().help("Retour au début")
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).foregroundStyle(.white).frame(width: 58, height: 58)
                        .accentGlassDisc(accent)
                }
                .buttonStyle(PressStyle()).help(player.isPlaying ? "Pause" : "Lecture")
                Button { model.playlist.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 13)).frame(width: 42, height: 42) }
                    .buttonStyle(PressStyle()).glassCircle().help("Fichier suivant")
                    .disabled(!listPlays || !model.playlist.hasNext)
                let repeating = model.playlist.repeatMode != .off && player.mode == .independent
                Button { model.cycleRepeat() } label: {
                    Image(systemName: model.playlist.repeatMode == .file ? "repeat.1" : "repeat").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(repeating ? accent : Color.primary).frame(width: 42, height: 42)
                }
                .buttonStyle(PressStyle()).glassCircle()
                    .overlay { if repeating { Circle().strokeBorder(accent, lineWidth: 2) } }
                    .disabled(player.mode == .followTransport)
                    .help(player.mode == .followTransport ? "Sans effet avec le transport JACK : passez en mode Indépendant pour répéter." : repeatHelp)
            }
            .disabled(!player.canCommand)
            CommandButton().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 26).frame(height: 84)
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }

    private var listPlays: Bool { model.player.mode == .independent }

    private var repeatHelp: LocalizedStringKey {
        switch model.playlist.repeatMode {
        case .off: "Répétition : aucune"
        case .list: "Répétition : la liste"
        case .file: "Répétition : le fichier"
        }
    }

    /// In the mode that follows the transport: the state of the transport, and who drives it.
    @ViewBuilder private var transportState: some View {
        let player = model.player
        if player.mode == .followTransport {
            HStack(spacing: 7) {
                Circle().fill(player.isPlaying ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    .shadow(color: player.isPlaying ? .green.opacity(0.7) : .clear, radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.isPlaying ? "Transport JACK : en lecture" : "Transport JACK : arrêté").font(.callout)
                    if !player.commandsTransport {
                        Text("Les boutons ne commandent pas le transport").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: No file, and the command line

struct NoFileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.waveform").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("Aucun fichier").font(.title3).fontWeight(.medium).padding(.top, 6)
            Text("Déposez un fichier audio ici, ou choisissez-en un.").font(.callout).foregroundStyle(.secondary)
            Button("Ouvrir un fichier…") { model.chooseFile() }.buttonStyle(.borderedProminent).controlSize(.large).accentTint().padding(.top, 10)
        }
        .padding(.vertical, 64).padding(.horizontal, 40)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .padding(26)
        .frame(maxWidth: 640)
    }
}

/// The button that shows the command line, at the same place (bottom right of the window) on every page.
struct CommandButton: View {
    @State private var showsCommand = false

    var body: some View {
        Button("Ligne de commande générée") { showsCommand = true }
            .sheet(isPresented: $showsCommand) { CommandSheet() }
    }
}

struct CommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let text = model.player.commandLine ?? ""
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ligne de commande équivalente").font(.title3).fontWeight(.semibold)
                Text("Ce que Jack Play lance pour lire ce fichier. Les branchements sont faits ensuite par l'application.").foregroundStyle(.secondary)
            }
            // The terminal view is dark in both appearances, with the colours of a shell.
            ScrollView {
                Text(CommandHighlighter.attributed(text))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 80, maxHeight: 280)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            HStack {
                Spacer()
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 560)
    }
}
