// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SoundFileKit
import SwiftUI
import WaveformKit

/// On the page of the launch, in the mode on sound files: the file that was rendered is what the processing is for, so it gets the
/// place of honour: a card that says what is being done, and then shows the file, its waveform, and what to do with it.
struct RenderResultCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @State private var summary: OutputSummary?
    @State private var waveform = WaveformModel()
    @State private var measuredPath: String?
    @State private var appeared = false

    private var state: EngineController.State { model.controller.state }

    var body: some View {
        Group {
            switch state {
            case .running, .stopping: working
            case .ended where model.controller.endedOnAProblem: failed
            case .ended: done
            case .idle: waiting
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .task(id: "\(String(describing: state))\(model.outputFile?.path ?? "")") { await measure() }
    }

    // MARK: Before and during

    private var waiting: some View {
        HStack(spacing: 14) {
            icon("waveform.badge.plus", tint: .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Le fichier rendu apparaîtra ici").font(.headline)
                Text(model.outputFile.map { String(localized: "Il sera écrit sous le nom « \($0.lastPathComponent) ».") }
                     ?? String(localized: "Choisissez d'abord le fichier de sortie, puis lancez le traitement avec le bouton rond."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var working: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text("Traitement en cours…").font(.headline)
                Text("fconvolver écrit le fichier de sortie.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var failed: some View {
        HStack(spacing: 14) {
            icon("exclamationmark.triangle.fill", tint: .red)
            VStack(alignment: .leading, spacing: 3) {
                Text("Le traitement n'a pas abouti").font(.headline)
                Text("Le journal dit pourquoi.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Voir le journal") { model.page = .log }
        }
    }

    // MARK: The result

    @ViewBuilder private var done: some View {
        if let url = model.outputFile, let summary {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Fichier rendu").font(.headline)
                    Spacer()
                    Text(verbatim: duration).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 16) {
                    // The file itself: it can be dragged out of the window, into the Finder or an application.
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 56, height: 56)
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .help("Glissez le fichier où vous voulez l'utiliser")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent).font(.title3).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: facts(summary)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Afficher dans le Finder", systemImage: "folder") }
                        listenButtons(url, channels: summary.info.channels)
                    }
                    .controlSize(.regular)
                }
                if waveform.finishedPeaks != nil || waveform.state == .loading {
                    WaveformView(peaks: waveform.peaks, channels: summary.info.channels, position: 0,
                                 laneHeight: max(8, min(40, 96 / CGFloat(max(summary.info.channels, 1)))),
                                 playedColor: accent, unplayedColor: accent.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .scaleEffect(appeared ? 1 : 0.97).opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(.spring(duration: 0.45)) { appeared = true } }
        } else {
            HStack(spacing: 14) {
                icon("questionmark.folder", tint: .secondary)
                Text("Le fichier de sortie est introuvable.").font(.headline)
            }
        }
    }

    /// Listening: the system plays one or two channels as they are, but mixes or cuts a file with more of them, so then the button says
    /// only that it opens the file, and Jack Play, which plays every channel, is offered when it is installed.
    @ViewBuilder private func listenButtons(_ url: URL, channels: Int) -> some View {
        let jackPlay = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.github.zinc75.jackappscollection.jackplay")
        if channels <= 2 {
            Button { NSWorkspace.shared.open(url) } label: { Label("Écouter", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent).accentTint()
        } else {
            Button { NSWorkspace.shared.open(url) } label: { Label("Ouvrir", systemImage: "arrow.up.forward.app") }
                .help("Ouvre le fichier avec l'application du système : elle ne jouera pas toutes ses voies.")
        }
        if let jackPlay {
            let open = { NSWorkspace.shared.open([url], withApplicationAt: jackPlay, configuration: NSWorkspace.OpenConfiguration()) }
            if channels <= 2 {
                Button(action: open) { Label("Ouvrir dans Jack Play", systemImage: "play.rectangle") }
                    .help("Jack Play joue toutes les voies du fichier, avec les connexions JACK que vous choisissez.")
            } else {
                // More than two channels: this is the way to hear them, so it is the main button.
                Button(action: open) { Label("Ouvrir dans Jack Play", systemImage: "play.rectangle") }
                    .buttonStyle(.borderedProminent).accentTint()
                    .help("Jack Play joue toutes les voies du fichier, avec les connexions JACK que vous choisissez.")
            }
        }
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.15)).frame(width: 44, height: 44)
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
        }
    }

    private func facts(_ s: OutputSummary) -> String {
        let rate = (s.info.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)))
        let seconds = s.info.duration.formatted(.number.precision(.fractionLength(1)))
        let size = ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file)
        let peak = s.peakDecibels.isFinite ? s.peakDecibels.formatted(.number.precision(.fractionLength(1))) + " dBFS" : "−∞ dBFS"
        return "\(s.info.channels) \(String(localized: "voies")) · \(rate) kHz · \(seconds) s · \(size) · \(String(localized: "crête")) \(peak)"
    }

    private var duration: String {
        guard let seconds = model.controller.runSeconds else { return "" }
        return String(localized: "traité en \(seconds.formatted(.number.precision(.fractionLength(seconds < 10 ? 2 : 1)))) s")
    }

    /// Looks at the file when the processing ends well.
    private func measure() async {
        guard case .ended = state, !model.controller.endedOnAProblem, let url = model.outputFile else {
            if case .running = state { summary = nil; appeared = false; measuredPath = nil }
            return
        }
        guard measuredPath != url.path + "\(model.runCount)" else { return }
        measuredPath = url.path + "\(model.runCount)"
        model.catalog.forget(url.path)
        let measured = await Task.detached(priority: .userInitiated) { try? OutputSummary.measure(url: url) }.value
        summary = measured
        if measured != nil { waveform.load { try SoundFile(url: url) } }
    }
}

/// The window of the processing of a sound file: the two files, the options, and then the result. The round button opens it.
struct RenderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// This window shows the command line in a sheet of its own (a sheet cannot open a second one from the window under it).
    @State private var showsCommandHere = false

    private var running: Bool { model.controller.isRunning }
    private var canRun: Bool { model.inputFile != nil && model.outputFile != nil && !model.hasErrors && !running }
    private var hasRun: Bool { if case .ended = model.controller.state { return true } else { return false } }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Traiter un fichier audio").font(.title3).fontWeight(.semibold)
                Text("Un fichier audio entre, un fichier convolué sort. Les réponses impulsionnelles sont celles de la configuration \(model.name).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RenderResultCard()
                    AudioFilesGroup().disabled(running)
                    SettingsGroup("Options") {
                        OptionRow("Mode vectoriel", "Traite quatre fréquences à la fois avec des instructions vectorielles.") {
                            Toggle("-V", isOn: $model.options.vectorMode).toggleStyle(.switch).labelsHidden().accentTint()
                        }
                        OptionRow("Optimiser les transformées", "FFTW teste plusieurs algorithmes au démarrage, ce qui ajoute environ 15 ms.") {
                            Toggle("-M", isOn: $model.options.measure).toggleStyle(.switch).labelsHidden().accentTint()
                        }
                        OptionRow("Couper à la longueur de l'entrée", "Sans cette option, la sortie garde la queue de la réverbération et dure plus longtemps que l'entrée.") {
                            Toggle("-T", isOn: $model.options.truncate).toggleStyle(.switch).labelsHidden().accentTint()
                        }
                    }
                    .disabled(running)
                    if let url = model.outputFile, FileManager.default.fileExists(atPath: url.path), !hasRun {
                        Label("« \(url.lastPathComponent) » existe déjà : il sera remplacé.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                    }
                    if !model.problems.isEmpty { ProblemList() }
                }
            }
            HStack {
                Button("Ligne de commande générée") { showsCommandHere = true }
                Spacer()
                if running {
                    Button("Interrompre", role: .destructive) { model.controller.stop() }
                } else {
                    Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                Button(hasRun ? "Traiter à nouveau" : "Traiter") { model.startRun() }
                    .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
                    .help(model.inputFile == nil ? "Choisissez d'abord le fichier d'entrée." : model.outputFile == nil ? "Choisissez le fichier de sortie." : "")
            }
        }
        .padding(22).frame(width: 700, height: 850)
        .sheet(isPresented: $showsCommandHere) { CommandSheet() }
    }
}
