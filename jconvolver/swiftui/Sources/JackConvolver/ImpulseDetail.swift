// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SoundFileKit
import SwiftUI

/// Which impulse response the detail window shows: the one at this place of this pair.
struct DetailTarget: Identifiable, Equatable {
    let pair: ConvPair
    let index: Int
    var id: String { "\(pair.input)-\(pair.output)-\(index)" }
}

/// The detail of an impulse response that comes from a sound file: its waveform with the part the engine uses, and what the analysis
/// found (peak, where the attack starts, where the useful tail ends).
struct ImpulseDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.dismiss) private var dismiss
    let target: DetailTarget
    @State private var curve: CurveData?
    @State private var failed = false
    #if DEBUG
    @State private var showsSpectrum = ProcessInfo.processInfo.environment["JACKCONVOLVER_DETAIL"] == "spectrum"
    #else
    @State private var showsSpectrum = false
    #endif
    @State private var analysis: ImpulseAnalysis?
    @State private var info: SoundFileInfo?

    private var impulse: ConvImpulse? {
        guard let list = model.document?.impulses(at: target.pair), list.indices.contains(target.index) else { return nil }
        return list[target.index]
    }

    private var resolved: (path: String, channel: Int)? {
        guard let impulse, case .file(let file, let channel) = impulse.source else { return nil }
        return (ConvConfig.path(of: file, directory: impulse.directory, configDirectory: model.configDirectory), channel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let impulse, let resolved {
                header(impulse, resolved)
                waveformView(impulse, resolved)
                facts(impulse)
            } else {
                Text("Cette RI n'existe plus.").foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction).accentTint() }
        }
        .padding(20)
        .frame(width: 720)
        .task(id: resolved?.path) { await load() }
    }

    private func header(_ impulse: ConvImpulse, _ resolved: (path: String, channel: Int)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Détail de la RI").font(.title3).fontWeight(.semibold)
            Text(verbatim: "\((resolved.path as NSString).lastPathComponent) · \(String(localized: "voie")) \(resolved.channel)").font(.headline)
            Text("\(model.inputLabel(target.pair.input)) → \(model.outputLabel(target.pair.output))").foregroundStyle(.secondary)
        }
    }

    // MARK: The curve

    private func waveformView(_ impulse: ConvImpulse, _ resolved: (path: String, channel: Int)) -> some View {
        Group {
            if let curve {
                let total = curve.count
                let end = impulse.length > 0 ? min(impulse.offset + impulse.length, total) : total
                let range = min(impulse.offset, total)..<max(end, min(impulse.offset, total))
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Vue", selection: $showsSpectrum) {
                        Text("Temps").tag(false)
                        Text("Fréquence").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
                    if showsSpectrum {
                        ImpulseSpectrumView(data: curve, used: range)
                    } else {
                        ImpulseCurveView(data: curve, used: range, attack: analysis?.attackFrame, tail: analysis?.tailFrame)
                    }
                }
            } else if failed {
                Text("Ce fichier ne peut pas être lu.").foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 190)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 190)
            }
        }
    }

    // MARK: The figures

    private func facts(_ impulse: ConvImpulse) -> some View {
        let rate = info?.sampleRate ?? 0
        func time(_ frames: Int) -> String {
            guard rate > 0 else { return "" }
            return "\(frames) (" + (Double(frames) / rate * 1000).formatted(.number.precision(.fractionLength(1))) + " ms)"
        }
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
            if let info {
                row("Fichier", "\(info.container) · \(info.encoding) · \(Int(info.sampleRate)) Hz · \(info.channels) " + String(localized: "voies"))
                row("Durée", time(Int(info.frames)))
            }
            if let analysis {
                row("Crête", (analysis.peakDB.isFinite ? analysis.peakDB.formatted(.number.precision(.fractionLength(1))) : "−∞") + " dB")
                row("Début de l'attaque (−60 dB)", time(analysis.attackFrame), legend: .green)
                row("Fin utile (−90 dB)", time(analysis.tailFrame), legend: .orange)
                row("Silence au début", time(analysis.leadingFrames))
                row("Silence à la fin", time(analysis.trailingFrames))
            }
            row("Zone lue par le moteur", impulse.length > 0 ? "\(time(impulse.offset)) → +\(time(impulse.length))" : "\(time(impulse.offset)) → " + String(localized: "fin du fichier"))
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String, legend: Color? = nil) -> some View {
        GridRow {
            HStack(spacing: 6) {
                if let legend { Rectangle().fill(legend).frame(width: 3, height: 12) }
                Text(title).foregroundStyle(.secondary)
            }
            Text(verbatim: value).monospacedDigit().textSelection(.enabled)
        }
    }

    private func load() async {
        guard let resolved else { return }
        let path = resolved.path, channel = resolved.channel, catalog = model.catalog
        info = catalog.info(at: path)
        let loaded = await Task.detached(priority: .userInitiated) { try? CurveData.load(url: URL(fileURLWithPath: path), channel: channel) }.value
        curve = loaded
        failed = loaded == nil
        let all = await Task.detached(priority: .utility) { catalog.analysis(at: path) }.value
        analysis = all.flatMap { $0.indices.contains(channel - 1) ? $0[channel - 1] : nil }
    }
}
