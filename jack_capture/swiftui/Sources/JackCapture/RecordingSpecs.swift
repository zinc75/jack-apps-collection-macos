// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

/// What `sndfile-info` would say about the recording, in words, with its date; and, folded, how the session was set up.
struct RecordingSpecs: View {
    let summary: RecordingSummary
    @State private var showsSession = false

    private var s: CaptureSettings { summary.settings }
    private var info: SoundFileInfo? { summary.fileInfo }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 9) {
                    row("Date", Text(summary.startedAt.formatted(date: .complete, time: .standard)))
                    if let info {
                        row("Conteneur", Text(verbatim: info.container))
                        if let encoding = info.encoding { row("Codage", Text(verbatim: encodingText(encoding))) }
                        // "little endian", "big endian": the terms are the same in every language.
                        if let endianness = info.endianness { row("Ordre des octets", Text(verbatim: endianness.lowercased())) }
                        if let rate = info.sampleRate { row("Fréquence d'échantillonnage", Text(verbatim: rateText(rate))) }
                        if let channels = info.channels { row("Voies", Text(verbatim: "\(channels)")) }
                        if let frames = info.frames { row("Trames", Text(verbatim: frames.formatted())) }
                        if let duration = info.duration { row("Durée", Text(verbatim: preciseClock(duration))) }
                        if let bitRate = info.bitRate { row("Débit moyen", Text(verbatim: "\(bitRate.formatted(.number.precision(.fractionLength(0)))) kbit/s")) }
                        row("Longueur du fichier", Text(verbatim: String(localized: "\(info.bytes.formatted()) octets")))
                        if summary.partCount > 1 {
                            row("Fichiers", Text("\(summary.partCount) fichiers"))
                            row("Durée totale", Text(verbatim: preciseClock(summary.duration)))
                        }
                    }
                    if info != nil { row("Crête", peaksView) }
                }
                DisclosureGroup(isExpanded: $showsSession) {
                    Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 9) {
                        row("Sources", sourcesView)
                        row("Client JACK", Text(verbatim: s.jackClientName))
                        row("Démarrage", Text(verbatim: startText))
                        if s.scheduledStop { row("Arrêt programmé", Text(verbatim: TimeSpan.text(s.durationSeconds))) }
                        if s.rotatesFiles { row("Découper en plusieurs fichiers", Text(verbatim: TimeSpan.text(s.rotationSeconds))) }
                        row("Tampon mémoire", Text(verbatim: "\(s.bufferSeconds) s"))
                        row("Incidents", Text(verbatim: "\(IncidentText.xruns(summary.xruns)) · \(IncidentText.overruns(summary.overruns))"))
                    }
                    .padding(.top, 8)
                    Text(CommandHighlighter.attributed(summary.commandText))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 10)
                } label: {
                    Text("Session").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: some View) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Words

    private func encodingText(_ e: SoundFileInfo.Encoding) -> String {
        switch e {
        case .pcmSigned(let bits): return String(localized: "PCM signé, \(bits) bits")
        case .pcmUnsigned(let bits): return String(localized: "PCM non signé, \(bits) bits")
        case .float(let bits): return String(localized: "Virgule flottante, \(bits) bits")
        case .flac(let bits): return bits.map { String(localized: "FLAC, \($0) bits") } ?? "FLAC"
        case .vorbis: return "Vorbis"
        case .opus: return "Opus"
        case .mpeg: return "MPEG Layer III"
        }
    }

    private func rateText(_ hz: Double) -> String {
        (hz / 1000).formatted(.number.precision(.fractionLength(0...3))) + " kHz"
    }

    /// hh:mm:ss.mmm, as sndfile-info writes durations.
    private func preciseClock(_ seconds: TimeInterval) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    private var startText: String {
        var parts: [String] = []
        switch s.startMode {
        case .immediately: parts.append(String(localized: "Immédiatement"))
        case .transport: parts.append(String(localized: "Au démarrage du transport JACK"))
        case .freewheel: parts.append(String(localized: "Au passage en freewheeling"))
        }
        if s.timemachine { parts.append("\(String(localized: "Préenregistrement (timemachine)")) : \(s.timemachineSeconds) s") }
        return parts.joined(separator: " · ")
    }

    // MARK: Peaks

    @ViewBuilder private var peaksView: some View {
        if let peaks = summary.peaks {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(peaks.enumerated()), id: \.offset) { c, peak in
                    let full = peak >= 0.9999 && !isFloat
                    HStack(spacing: 6) {
                        Text(verbatim: "\(c + 1)").foregroundStyle(.secondary).monospacedDigit()
                        Text(verbatim: dB(peak)).monospacedDigit()
                        if full { Text("pleine échelle : écrêtage possible").font(.callout).foregroundStyle(Color.alert) }
                    }
                }
            }
        } else if summary.isMeasuringPeaks {
            Text("mesure en cours…").foregroundStyle(.secondary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private var isFloat: Bool { if case .float? = info?.encoding { return true } else { return false } }

    private func dB(_ peak: Float) -> String {
        let value = peak.formatted(.number.precision(.fractionLength(4)))
        guard peak > 0 else { return "−∞ dBFS (\(value))" }
        let db = 20 * log10(Double(peak))
        return "\(db.formatted(.number.precision(.fractionLength(2)))) dBFS (\(value))".replacingOccurrences(of: "-", with: "−")
    }

    // MARK: Session

    @ViewBuilder private var sourcesView: some View {
        if !s.autoConnect {
            Text("Connexions faites à la main dans le patchbay")
        } else if s.sources.allSatisfy(\.isEmpty) {
            Text("Entrées système, par défaut")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<s.channels, id: \.self) { c in
                    let ports = c < s.sources.count ? s.sources[c] : []
                    Text(verbatim: "\(c + 1)  ←  " + (ports.isEmpty ? "—" : ports.joined(separator: " + ")))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
