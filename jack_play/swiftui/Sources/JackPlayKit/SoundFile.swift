// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import Foundation
import WaveformKit

/// What libsndfile says about a sound file, in its own words (which are English).
public struct SoundFileInfo: Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Double
    /// Frames of the file; 0 when the format does not say.
    public let frames: Int64
    /// The container, as libsndfile names it: "WAV (Microsoft)", "FLAC (FLAC Lossless Audio Codec)" …
    public let container: String
    /// The usual extension of the container: "wav", "flac", "ogg" …
    public let fileExtension: String
    /// The encoding, as libsndfile names it: "Signed 24 bit PCM", "Vorbis" …
    public let encoding: String
    /// Bits of a sample for the formats that have a fixed number (PCM and floating point), nil for the others.
    public let bitsPerSample: Int?
    /// True for the formats that lose information (Vorbis, Opus, MP3).
    public let isLossy: Bool

    public var duration: TimeInterval { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
}

public enum SoundFileError: Error, Equatable {
    /// The file cannot be opened as a sound file; the message is libsndfile's.
    case cannotOpen(String)
    case seekFailed(Int64)
    case readFailed(String)
}

/// A sound file opened with libsndfile, which reads everything that `jack_play` reads: WAV, RF64, W64, AIFF, CAF, FLAC,
/// Ogg Vorbis, Opus and MP3, among others. It is a `SampleSource`, so that `WaveformKit` can read it.
///
/// An instance has one position in the file and is not safe for several threads at once: give each thread a source of
/// its own (open the file again).
public final class SoundFile: SampleSource, @unchecked Sendable {
    public let info: SoundFileInfo
    private var handle: OpaquePointer?

    public var channels: Int { info.channels }
    public var frames: Int64 { info.frames }
    public var sampleRate: Double { info.sampleRate }

    public init(url: URL) throws {
        var raw = SF_INFO()
        guard let opened = sf_open(url.path, Int32(SFM_READ), &raw) else {
            throw SoundFileError.cannotOpen(String(cString: sf_strerror(nil)))
        }
        guard raw.channels >= 1, raw.samplerate > 0 else {
            sf_close(opened)
            throw SoundFileError.cannotOpen("not a sound file")
        }
        handle = opened
        info = Self.describe(raw)
    }

    deinit { if let handle { sf_close(handle) } }

    /// The information of a file, without keeping it open.
    public static func probe(_ url: URL) throws -> SoundFileInfo { try SoundFile(url: url).info }

    public func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        guard let handle else { return 0 }
        let got = Int(sf_readf_float(handle, buffer, sf_count_t(maxFrames)))
        if got == 0, sf_error(handle) != 0 { throw SoundFileError.readFailed(String(cString: sf_strerror(handle))) }
        return got
    }

    public func seek(toFrame frame: Int64) throws {
        guard let handle else { return }
        if sf_seek(handle, sf_count_t(frame), SEEK_SET) < 0 { throw SoundFileError.seekFailed(frame) }
    }

    // MARK: Description

    private static func describe(_ raw: SF_INFO) -> SoundFileInfo {
        let major = raw.format & Int32(SF_FORMAT_TYPEMASK), sub = raw.format & Int32(SF_FORMAT_SUBMASK)
        let container = formatInfo(major, command: Int32(SFC_GET_FORMAT_MAJOR))
        let encoding = formatInfo(sub, command: Int32(SFC_GET_FORMAT_SUBTYPE))
        let bits: Int?
        switch Int32(sub) {
        case Int32(SF_FORMAT_PCM_S8), Int32(SF_FORMAT_PCM_U8): bits = 8
        case Int32(SF_FORMAT_PCM_16): bits = 16
        case Int32(SF_FORMAT_PCM_24): bits = 24
        case Int32(SF_FORMAT_PCM_32), Int32(SF_FORMAT_FLOAT): bits = 32
        case Int32(SF_FORMAT_DOUBLE): bits = 64
        default: bits = nil
        }
        let lossy = [Int32(SF_FORMAT_VORBIS), Int32(SF_FORMAT_OPUS), Int32(SF_FORMAT_MPEG_LAYER_I),
                     Int32(SF_FORMAT_MPEG_LAYER_II), Int32(SF_FORMAT_MPEG_LAYER_III)].contains(sub)
        return SoundFileInfo(channels: Int(raw.channels), sampleRate: Double(raw.samplerate), frames: Int64(raw.frames),
                             container: container.name, fileExtension: container.ext, encoding: encoding.name,
                             bitsPerSample: bits, isLossy: lossy)
    }

    /// The name and the extension libsndfile gives to a major format or to a subtype.
    private static func formatInfo(_ format: Int32, command: Int32) -> (name: String, ext: String) {
        var count: Int32 = 0
        sf_command(nil, command == Int32(SFC_GET_FORMAT_MAJOR) ? Int32(SFC_GET_FORMAT_MAJOR_COUNT) : Int32(SFC_GET_FORMAT_SUBTYPE_COUNT),
                   &count, Int32(MemoryLayout<Int32>.size))
        for i in 0..<count {
            var entry = SF_FORMAT_INFO()
            entry.format = i
            sf_command(nil, command, &entry, Int32(MemoryLayout<SF_FORMAT_INFO>.size))
            if entry.format == format {
                return (entry.name.map { String(cString: $0) } ?? "", entry.extension.map { String(cString: $0) } ?? "")
            }
        }
        return ("", "")
    }
}
