// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import AppearanceKit
import MatrixKit
import MeterKit
import JackCaptureKit

struct RecordingView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch model.phase {
                case .configuration: idle.containerRelativeFrame(.vertical, alignment: .center)
                case .armed, .recording, .stopping: live
                case .done: done
                }
            }
            .padding(24)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
    }

    // MARK: nothing started

    @State private var available: Int64?

    private var idle: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                readyPill
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(TimeFormat.clock(0)).font(.system(size: 68, weight: .ultraLight)).monospacedDigit()
                    Text(".0").font(.system(size: 28, weight: .ultraLight)).monospacedDigit()
                }
                .foregroundStyle(.tertiary)
            }
            if model.isConfigured {
                RecordButton(showsStop: false, diameter: 88, breathes: true) { model.toggleRecording() }
            } else {
                VStack(spacing: 10) {
                    ConfigureButton().controlSize(.extraLarge)
                    Text("Choisir les sources et le dossier avant le premier enregistrement.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            levels
            recap
        }
        .onAppear { model.showsIdlePage = true }
        .onDisappear { model.showsIdlePage = false }
        .task(id: model.settings) { available = model.availableBytes() }
    }

    /// The levels of the chosen sources before the recording, when they are asked for.
    private var levels: some View {
        VStack(spacing: 12) {
            Toggle("Prévisualiser les niveaux avant l'enregistrement",
                   isOn: Binding(get: { model.settings.monitorsLevels }, set: { model.settings.monitorsLevels = $0 }))
                .toggleStyle(.checkbox).accentTint()
                .help("Un client JACK de mesure, relié aux sources choisies, en prévisualise les niveaux tant que cette page attend. Il disparaît du graphe dès qu'un enregistrement commence.")
            if model.settings.monitorsLevels {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aperçu des niveaux").fontWeight(.semibold)
                        if model.isMonitoring {
                            MeterBars(meters: model.idleMeters, channels: model.settings.channels, scale: IECScale(), label: "Aperçu des niveaux")
                        } else {
                            Text(levelsWaiting).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 560)
            }
        }
    }

    /// Why the levels are not shown yet.
    private var levelsWaiting: LocalizedStringKey {
        if !model.settings.autoConnect { return "Les connexions sont laissées au patchbay : il n'y a pas de sources à prévisualiser." }
        if SourceAssignment(model.settings.sources, channels: model.settings.channels).usedCount == 0 { return "Choisir des sources dans Voies pour voir leurs niveaux." }
        return "En attente de JACK…"
    }

    @ViewBuilder private var readyPill: some View {
        let ready = model.graph.isConnected
        HStack(spacing: 7) {
            Circle().fill(.white).frame(width: 7, height: 7)
            Text(ready ? "PRÊT" : "JACK NON DÉMARRÉ").font(.caption).fontWeight(.semibold).tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(ready ? Color.green : Color.orange, in: .capsule)
    }

    /// What the next recording will be, one line per subject; each leads to the page where it is set.
    private var recap: some View {
        let s = model.settings
        let problems = model.sourceCheck.descriptions
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                RecapRow(symbol: "circle.grid.3x3", title: "Sources", page: .channels, flagged: !problems.isEmpty) {
                    HStack(spacing: 8) {
                        if !sourceClients.isEmpty { BadgeStack(clients: sourceClients, size: 22) }
                        Text(verbatim: s.channels == 1 ? String(localized: "1 voie") : String(localized: "\(s.channels) voies"))
                    }
                    if problems.isEmpty && sourceClients.isEmpty {
                        Text("Aucune source choisie").foregroundStyle(Color.alert)
                    }
                    ForEach(problems, id: \.self) { Text($0).font(.callout).foregroundStyle(Color.alert) }
                }
                Divider()
                RecapRow(symbol: "doc", title: "Format", page: .file) {
                    Text(verbatim: s.summaryLine(sampleRate: model.sampleRate))
                    Text(verbatim: "\((s.folder as NSString).abbreviatingWithTildeInPath) · \(sizeLine)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let trigger = triggerText {
                    Divider()
                    RecapRow(symbol: "timer", title: "Déclenchement", page: .startStop) { Text(verbatim: trigger) }
                }
            }
        }
        .frame(maxWidth: 560)
    }

    /// The clients that feed the channels, in order of appearance.
    private var sourceClients: [(name: String, isCapture: Bool, bundleID: String?)] {
        var names: [String] = []
        for port in model.settings.sources.prefix(model.settings.channels).flatMap({ $0 }) {
            let name = port.split(separator: ":", maxSplits: 1).first.map(String.init) ?? port
            if !names.contains(name) { names.append(name) }
        }
        return names.map { name in
            (name, name == "system", model.graph.clients.first { $0.name == name }?.bundleID ?? model.settings.knownBundles[name])
        }
    }

    private var sizeLine: String {
        let perMinute = SizeText.bytes(model.bytesPerMinute)
        let free = available.map { SizeText.bytes(Double($0)) } ?? "?"
        return String(localized: "Environ \(perMinute) par minute · \(free) disponibles")
    }

    /// What differs from "starts at once, runs until stopped, one file".
    private var triggerText: String? {
        let s = model.settings
        var parts: [String] = []
        if s.startMode != .immediately { parts.append(String(localized: "Démarrage : \(s.startMode.label)")) }
        if s.timemachine { parts.append(String(localized: "Préenregistrement : \(s.timemachineSeconds) s")) }
        if s.scheduledStop { parts.append(String(localized: "Arrêt après \(TimeSpan.text(s.durationSeconds))")) }
        if s.rotatesFiles { parts.append(String(localized: "Un fichier toutes les \(TimeSpan.text(s.rotationSeconds))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: armed, recording, stopping

    private var live: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                statusPill
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(TimeFormat.clock(model.elapsed))
                        .font(.system(size: 68, weight: .ultraLight)).monospacedDigit()
                    Text(".\(TimeFormat.tenth(model.elapsed))")
                        .font(.system(size: 28, weight: .ultraLight)).monospacedDigit().foregroundStyle(.secondary)
                }
                if model.phase == .recording, model.settings.scheduledStop { scheduledStopProgress }
                Text(verbatim: "\(model.outputFile ?? model.nextFileName()) · \(model.settings.summaryLine(sampleRate: model.sampleRate))")
                    .foregroundStyle(.secondary)

                if let hint = armedHint {
                    Text(hint).font(.callout).foregroundStyle(Color.alert).multilineTextAlignment(.center)
                }
                ForEach(model.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Color.alert)
                }
            }
            MetersCard()
            HStack(spacing: 12) {
                tile("Tampon mémoire", bufferText, bufferSub)
                tile("Écrit sur le disque", SizeText.bytes(Double(model.bytesWritten)), "environ \(SizeText.bytes(RecordingEstimate.bytesPerSecond(model.settings, sampleRate: model.sampleRate))) par seconde",
                     extra: model.diskSecondsLeft.flatMap { $0 < 48 * 3600 ? String(localized: "disque : reste \(RecorderModel.remaining($0))") : nil })
                tile("Incidents", "\(model.status?.xruns ?? 0) xrun", "\(model.status?.overruns ?? 0) débordement")
                tile("Thread disque", (model.status?.diskThreadHighPriority ?? false) ? String(localized: "Priorité haute") : String(localized: "Normale"),
                     "Priorité élevée quand le tampon se remplit.")
            }
        }
    }

    /// How far the recording is from its programmed stop: a bar under the clock, and the time that is left. It is
    /// drawn image by image from the start time, not from the clock of the model, so that it moves smoothly.
    private var scheduledStopProgress: some View {
        let total = Double(max(model.settings.durationSeconds, 1))
        let start = model.writingStartedAt ?? Date()
        return TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let done = min(max(timeline.date.timeIntervalSince(start), 0), total)
            let remaining = max(0, Int((total - done).rounded(.up)))
            VStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    Color.primary.opacity(0.12)
                    Color.red.frame(width: 360 * done / total)
                }
                .frame(width: 360, height: 6)
                .clipShape(Capsule())
                Text("Arrêt automatique dans \(TimeSpan.text(remaining))").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var bufferText: String {
        guard let s = model.status else { return "—" }
        return String(format: "%.2f s", s.bufferFree).replacingOccurrences(of: ".", with: ",")
    }

    private var bufferSub: LocalizedStringKey {
        guard let s = model.status else { return "en attente de jack_capture" }
        return "sur \(String(format: "%.2f", s.bufferTotal).replacingOccurrences(of: ".", with: ",")) s"
    }

    /// What an armed recorder waits for.
    private var armedHint: LocalizedStringKey? {
        guard model.phase == .armed else { return nil }
        switch model.armedReason {
        case .timemachine?: return "En écoute : appuyer sur le bouton rouge pour démarrer. Le fichier commencera par les dernières secondes déjà écoulées."
        case .jack(let what)?: return what == "transport" ? "En attente du démarrage du transport JACK." : "En attente du passage en freewheeling."
        case nil: return nil
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let stopping = model.phase == .stopping, armed = model.phase == .armed
        HStack(spacing: 7) {
            Circle().fill(.white).frame(width: 7, height: 7)
            Text(stopping ? "ÉCRITURE SUR LE DISQUE" : armed ? "EN ATTENTE" : "REC").font(.caption).fontWeight(.semibold).tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(stopping || armed ? Color.orange : Color.red, in: .capsule)
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ sub: LocalizedStringKey, extra: String? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3).fontWeight(.medium).monospacedDigit()
                Text(sub).font(.caption).foregroundStyle(.secondary)
                if let extra { Text(verbatim: extra).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: done

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                .frame(width: 84, height: 84).background(.green, in: .circle)
            Text("Enregistrement terminé").font(.title2).fontWeight(.semibold)
            Text(verbatim: model.recordedURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "")
                .font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text(verbatim: "\(TimeFormat.clock(model.summary?.duration ?? model.elapsed)) · \(SizeText.bytes(Double(model.bytesWritten)))").foregroundStyle(.secondary)
            ForEach(model.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Color.alert)
            }
            if let summary = model.summary { RecordingSpecs(summary: summary).frame(maxWidth: 640) }
            HStack {
                Button("Afficher dans le Finder") {
                    if let url = model.recordedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.buttonStyle(.borderedProminent).accentTint()
                Button("Nouvel enregistrement") { model.newRecording() }
            }
        }
        .padding(.top, 40)
    }
}

/// One line of the summary on the idle page: a symbol, a small title, the content, and a chevron. It leads to the page where
/// the subject is set.
struct RecapRow<Content: View>: View {
    @Environment(RecorderModel.self) private var model
    let symbol: String
    let title: LocalizedStringKey
    let page: MainView
    var flagged = false
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        Button { model.view = page } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: flagged ? "exclamationmark.triangle.fill" : symbol)
                    .font(.system(size: 15)).frame(width: 24)
                    .foregroundStyle(flagged ? Color.alert : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    content
                }
                Spacer(minLength: 12)
                // Under the pointer the chevron brightens and slides a little: nothing is drawn around the row.
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.6))
                    .offset(x: isHovered ? 3 : 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // A row that goes away under the pointer gives the cursor back.
        .onDisappear { if isHovered { NSCursor.pop(); isHovered = false } }
    }
}
