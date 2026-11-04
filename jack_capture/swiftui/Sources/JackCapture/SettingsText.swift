// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import JackCaptureKit

/// Names and explanations of the settings, as the interface words them.
extension CaptureFormat {
    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .rf64: return "RF64"
        case .aiff: return "AIFF"
        case .caf: return "CAF"
        case .w64: return "W64"
        case .flac: return "FLAC"
        case .ogg: return "Ogg Vorbis"
        case .opus: return "Opus"
        case .mp3: return "MP3"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .wav: return "Au-delà de 2 voies, le WAV étendu est utilisé automatiquement."
        case .rf64: return "Comme le WAV, sans la limite de 4 Go."
        case .aiff: return "Le format audio d'Apple, sans compression."
        case .caf: return "Core Audio Format, sans limite de taille."
        case .w64: return "Wave64, utilisé par certains logiciels de montage."
        case .flac: return "Compression sans perte : le fichier est environ deux fois plus petit."
        case .ogg: return "Compression avec perte, ouverte et très répandue."
        case .opus: return "Compression avec perte, très efficace à faible débit."
        case .mp3: return "Compression avec perte, lisible partout."
        }
    }
}

extension SampleDepth {
    var label: LocalizedStringKey {
        switch self {
        case .float32: return "Virgule flottante 32 bits"
        case .int32: return "32 bits entiers"
        case .int24: return "24 bits"
        case .int16: return "16 bits"
        case .int8: return "8 bits"
        }
    }

    var shortLabel: String {
        switch self {
        case .float32: return String(localized: "32 bits flottants")
        case .int32: return String(localized: "32 bits")
        case .int24: return String(localized: "24 bits")
        case .int16: return String(localized: "16 bits")
        case .int8: return String(localized: "8 bits")
        }
    }
}

extension StartMode {
    var label: LocalizedStringKey {
        switch self {
        case .immediately: return "Immédiatement"
        case .transport: return "Au démarrage du transport JACK"
        case .freewheel: return "Au passage en freewheeling"
        }
    }
}

extension CaptureSettings {
    /// "2 voies · WAV 24 bits · 48 kHz"
    func summaryLine(sampleRate: Int) -> String {
        let channelsText = channels == 1 ? String(localized: "1 voie") : String(localized: "\(channels) voies")
        var kind = format.displayName
        if !format.isLossy {
            kind += " " + depth.shortLabel
        } else if format == .mp3 {
            kind += " " + String(localized: "\(mp3Bitrate) kbit/s")
        }
        let kHz = Double(sampleRate) / 1000
        let rate = kHz.formatted(.number.precision(.fractionLength(0...1))) + " kHz"
        return [channelsText, kind, rate].joined(separator: " · ")
    }
}

enum SizeText {
    /// Sizes with the precision that makes sense: tenths of a megabyte, whole gigabytes.
    static func bytes(_ n: Double) -> String {
        let value = n >= 10e9 ? (n / 1e9).rounded() * 1e9 : n
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
