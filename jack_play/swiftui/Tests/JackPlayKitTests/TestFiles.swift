// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import XCTest

/// Small sound files for the tests, written with libsndfile itself, in a folder that is removed at the end.
final class TestFiles {
    struct Format {
        let name: String
        let code: Int32
        let lossy: Bool
        let sampleRate: Int32
    }

    static let all: [Format] = [
        Format(name: "wav16", code: Int32(SF_FORMAT_WAV | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "wav24", code: Int32(SF_FORMAT_WAV | SF_FORMAT_PCM_24), lossy: false, sampleRate: 44100),
        Format(name: "wavf", code: Int32(SF_FORMAT_WAV | SF_FORMAT_FLOAT), lossy: false, sampleRate: 96000),
        Format(name: "rf64", code: Int32(SF_FORMAT_RF64 | SF_FORMAT_PCM_24), lossy: false, sampleRate: 48000),
        Format(name: "w64", code: Int32(SF_FORMAT_W64 | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "aiff", code: Int32(SF_FORMAT_AIFF | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "caf", code: Int32(SF_FORMAT_CAF | SF_FORMAT_PCM_24), lossy: false, sampleRate: 48000),
        Format(name: "flac", code: Int32(SF_FORMAT_FLAC | SF_FORMAT_PCM_24), lossy: false, sampleRate: 44100),
        Format(name: "vorbis", code: Int32(SF_FORMAT_OGG | SF_FORMAT_VORBIS), lossy: true, sampleRate: 48000),
        Format(name: "opus", code: Int32(SF_FORMAT_OGG | SF_FORMAT_OPUS), lossy: true, sampleRate: 48000),
        Format(name: "mp3", code: Int32(SF_FORMAT_MPEG | SF_FORMAT_MPEG_LAYER_III), lossy: true, sampleRate: 44100),
    ]

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jackplay-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// A sine at 0.5 on the first channel, and at 0.25 on the others, `frames` frames long.
    static func sample(frame: Int, channel: Int, rate: Double) -> Float {
        Float(sin(2 * Double.pi * (440 * Double(channel + 1)) * Double(frame) / rate)) * (channel == 0 ? 0.5 : 0.25)
    }

    @discardableResult
    func write(_ format: Format, channels: Int = 2, frames: Int = 24000) throws -> URL {
        let url = directory.appendingPathComponent("\(format.name)-\(channels)ch.\(UUID().uuidString.prefix(4))")
        var info = SF_INFO(frames: 0, samplerate: format.sampleRate, channels: Int32(channels), format: format.code, sections: 0, seekable: 0)
        guard let file = sf_open(url.path, Int32(SFM_WRITE), &info) else {
            throw XCTSkip("this build of libsndfile cannot write \(format.name): \(String(cString: sf_strerror(nil)))")
        }
        var samples = [Float](repeating: 0, count: frames * channels)
        for f in 0..<frames { for c in 0..<channels { samples[f * channels + c] = Self.sample(frame: f, channel: c, rate: Double(format.sampleRate)) } }
        sf_writef_float(file, samples, sf_count_t(frames))
        sf_close(file)
        return url
    }
}
