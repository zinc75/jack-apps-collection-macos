// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Sample precision of the integer and floating point file formats.
public enum SampleDepth: String, CaseIterable, Sendable, Codable {
    case float32 = "f32"
    case int32 = "32"
    case int24 = "24"
    case int16 = "16"
    case int8 = "8"

    public var bytes: Int {
        switch self {
        case .float32, .int32: return 4
        case .int24: return 3
        case .int16: return 2
        case .int8: return 1
        }
    }

    /// Bits of the jack_capture `-b` option; nil for floating point, which is its default.
    var bitsOption: String? { self == .float32 ? nil : rawValue }
}

/// The file formats offered, with what each of them allows. The raw value is the name given to
/// `jack_capture -f` and the file extension.
public enum CaptureFormat: String, CaseIterable, Sendable, Codable {
    case wav, rf64, aiff, caf, w64, flac, ogg, opus, mp3

    public var fileExtension: String { rawValue }

    /// Depths the user can choose; empty for the compressed formats with loss.
    public var depths: [SampleDepth] {
        switch self {
        case .wav, .rf64, .aiff, .caf, .w64: return [.float32, .int32, .int24, .int16, .int8]
        case .flac: return [.int24, .int16]
        case .ogg, .opus, .mp3: return []
        }
    }

    public var isLossy: Bool { depths.isEmpty }

    /// The number of channels is limited by the format (libsndfile and the codecs), not by
    /// jack_capture. The JACK server has its own limit (`--port-max`).
    public var maxChannels: Int {
        switch self {
        case .flac: return 8
        case .mp3: return 2
        case .ogg, .opus: return 255
        case .wav, .rf64, .aiff, .caf, .w64: return 1024
        }
    }
}
