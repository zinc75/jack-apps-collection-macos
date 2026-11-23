// SPDX-License-Identifier: GPL-3.0-or-later

import CSamplerate
import CSndfile
import Foundation
import SoundFileKit

public enum AudioResamplerError: Error, Equatable {
    case cannotRead(String)
    case alreadyAtRate
    case tooLarge
    case conversionFailed(String)
    case cannotWrite(String)
}

/// What a conversion made: the file that has the converted samples, and whether it was already there (an earlier conversion, strictly the same).
public struct ResampleResult: Sendable, Equatable {
    public var url: URL
    public var reused: Bool
    public var info: SoundFileInfo
}

/// Brings a sound file that holds an impulse response to another sample rate, once, with the best converter of libsamplerate: the file is written
/// next to the original, which is not touched. The signal stays where it was in time and keeps the frequency response of the filter (the samples are
/// scaled by the ratio of the rates), and the file is written in the format of the original when libsndfile can write it, else as 32 bit floats in a
/// WAV file.
public enum AudioResampler {
    /// Largest file converted, in samples (in memory, as 32 bit floats).
    static let maximumSamples = 400_000_000

    /// The name of the converted file: `<original>_resampled_<rate>.<extension>`, with `-2`, `-3`… after the rate when that name is taken.
    public static func outputName(for source: URL, rate: Int, ext: String, attempt: Int) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        return "\(base)_resampled_\(rate)" + (attempt > 1 ? "-\(attempt)" : "") + "." + ext
    }

    /// Converts `source` to `rate` and writes the result next to it (or in `folder`).
    ///
    /// A file of the name that the conversion would have exists already: when it holds strictly the same audio (same format, same samples, bit
    /// for bit, as a new conversion gives) it is used and nothing is written; otherwise it is left alone and the new file takes the next name.
    public static func resample(source: URL, toRate rate: Double, in folder: URL? = nil) throws -> ResampleResult {
        var info = SF_INFO()
        guard let input = sf_open(source.path, Int32(SFM_READ), &info) else { throw AudioResamplerError.cannotRead(String(cString: sf_strerror(nil))) }
        defer { sf_close(input) }
        let channels = Int(info.channels), frames = Int(info.frames)
        guard channels >= 1, frames > 0, info.samplerate > 0 else { throw AudioResamplerError.cannotRead("empty file") }
        guard abs(Double(info.samplerate) - rate) > 0.5 else { throw AudioResamplerError.alreadyAtRate }
        guard frames * channels <= maximumSamples else { throw AudioResamplerError.tooLarge }

        var samples = [Float](repeating: 0, count: frames * channels)
        let got = Int(samples.withUnsafeMutableBufferPointer { sf_readf_float(input, $0.baseAddress, sf_count_t(frames)) })
        guard got == frames else { throw AudioResamplerError.cannotRead("short read") }

        // The best converter. It keeps the signal where it was in time.
        let ratio = rate / Double(info.samplerate)
        let expected = Int((Double(frames) * ratio).rounded())
        var converted = [Float](repeating: 0, count: (expected + 64) * channels)
        var produced = 0
        let status: Int32 = samples.withUnsafeMutableBufferPointer { inPointer in
            converted.withUnsafeMutableBufferPointer { outPointer in
                var data = SRC_DATA(data_in: inPointer.baseAddress, data_out: outPointer.baseAddress, input_frames: Int(frames), output_frames: Int(expected + 64),
                                    input_frames_used: 0, output_frames_gen: 0, end_of_input: 1, src_ratio: ratio)
                let result = src_simple(&data, Int32(SRC_SINC_BEST_QUALITY), Int32(channels))
                produced = Int(data.output_frames_gen)
                return result
            }
        }
        guard status == 0 else { throw AudioResamplerError.conversionFailed(String(cString: src_strerror(status))) }
        guard produced > 0 else { throw AudioResamplerError.conversionFailed("nothing produced") }
        // An impulse response is the coefficients of a filter, not a signal: sampled at another rate, the same filter has coefficients that are
        // smaller (or larger) in the proportion of the rates, so that its gain does not change. The samples of the signal are converted as they
        // are, and then scaled so (the sum of the coefficients, which is the gain at zero hertz, is kept).
        let compensation = Float(1 / ratio)
        for i in 0..<(produced * channels) { converted[i] *= compensation }

        // The format of the original when it can be written at the new rate, else 32 bit floats in a WAV file.
        var output = SF_INFO()
        output.channels = info.channels
        output.samplerate = Int32(rate.rounded())
        output.format = info.format
        var extensionOfFile = (try? SoundFile.probe(source).fileExtension) ?? "wav"
        if sf_format_check(&output) == 0 || SoundFile.isLossy(format: info.format) {
            output.format = Int32(SF_FORMAT_WAV) | Int32(SF_FORMAT_FLOAT)
            extensionOfFile = "wav"
        }
        if extensionOfFile.isEmpty { extensionOfFile = "wav" }

        let directory = folder ?? source.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".resampling-\(UUID().uuidString).partial")
        try write(converted, frames: produced, channels: channels, format: output, to: temporary)

        var attempt = 1
        while true {
            let candidate = directory.appendingPathComponent(outputName(for: source, rate: Int(rate.rounded()), ext: extensionOfFile, attempt: attempt))
            if !FileManager.default.fileExists(atPath: candidate.path) {
                do { try FileManager.default.moveItem(at: temporary, to: candidate) } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    throw AudioResamplerError.cannotWrite(error.localizedDescription)
                }
                let written = try SoundFile.probe(candidate)
                return ResampleResult(url: candidate, reused: false, info: written)
            }
            if (try? sameAudio(candidate, temporary)) == true {
                try? FileManager.default.removeItem(at: temporary)
                return ResampleResult(url: candidate, reused: true, info: try SoundFile.probe(candidate))
            }
            attempt += 1
            if attempt > 999 { try? FileManager.default.removeItem(at: temporary); throw AudioResamplerError.cannotWrite("too many files of that name") }
        }
    }

    private static func write(_ samples: [Float], frames: Int, channels: Int, format: SF_INFO, to url: URL) throws {
        var info = format
        guard let handle = sf_open(url.path, Int32(SFM_WRITE), &info) else { throw AudioResamplerError.cannotWrite(String(cString: sf_strerror(nil))) }
        // A converted signal can go a little over full scale: it is cut there, not wrapped round.
        _ = sf_command(handle, Int32(SFC_SET_CLIPPING), nil, Int32(SF_TRUE))
        let written = samples.withUnsafeBufferPointer { Int(sf_writef_float(handle, $0.baseAddress, sf_count_t(frames))) }
        let failure = sf_error(handle)
        sf_close(handle)
        guard written == frames, failure == 0 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioResamplerError.cannotWrite(String(cString: sf_strerror(nil)))
        }
    }

    /// Whether two files hold strictly the same audio: the same format, the same rate, the same number of channels and of frames, and the same
    /// samples, bit for bit as libsndfile reads them.
    static func sameAudio(_ a: URL, _ b: URL) throws -> Bool {
        var infoA = SF_INFO(), infoB = SF_INFO()
        guard let fileA = sf_open(a.path, Int32(SFM_READ), &infoA) else { return false }
        defer { sf_close(fileA) }
        guard let fileB = sf_open(b.path, Int32(SFM_READ), &infoB) else { return false }
        defer { sf_close(fileB) }
        guard infoA.channels == infoB.channels, infoA.samplerate == infoB.samplerate, infoA.frames == infoB.frames, infoA.format == infoB.format else { return false }
        let block = 1 << 14, channels = Int(infoA.channels)
        var bufferA = [Float](repeating: 0, count: block * channels), bufferB = bufferA
        while true {
            let gotA = bufferA.withUnsafeMutableBufferPointer { Int(sf_readf_float(fileA, $0.baseAddress, sf_count_t(block))) }
            let gotB = bufferB.withUnsafeMutableBufferPointer { Int(sf_readf_float(fileB, $0.baseAddress, sf_count_t(block))) }
            guard gotA == gotB else { return false }
            if gotA == 0 { return true }
            let same = bufferA.withUnsafeBytes { x in bufferB.withUnsafeBytes { y in memcmp(x.baseAddress, y.baseAddress, gotA * channels * 4) == 0 } }
            if !same { return false }
        }
    }
}

extension SoundFile {
    /// Whether a format code of libsndfile is one that loses information (Vorbis, Opus, MP3): such a file is not written again in its format.
    static func isLossy(format: Int32) -> Bool {
        let sub = format & Int32(SF_FORMAT_SUBMASK)
        return [Int32(SF_FORMAT_VORBIS), Int32(SF_FORMAT_OPUS), Int32(SF_FORMAT_MPEG_LAYER_I), Int32(SF_FORMAT_MPEG_LAYER_II),
                Int32(SF_FORMAT_MPEG_LAYER_III)].contains(sub)
    }
}
