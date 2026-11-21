// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import Foundation
import WaveformKit

/// What libsndfile says about a sound file.
public struct AudioFileInfo: Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Double
    /// Frames of the file; 0 when the format does not say.
    public let frames: Int64
    /// The container, as libsndfile names it: "WAV (Microsoft)", "FLAC (FLAC Lossless Audio Codec)"...
    public let container: String
    /// The usual extension of the container: "wav", "flac", "caf"...
    public let fileExtension: String
    /// The encoding, as libsndfile names it: "Signed 24 bit PCM", "32 bit float"...
    public let encoding: String
    /// Bits of a sample for the formats that have a fixed number (PCM and floating point), nil for the others.
    public let bitsPerSample: Int?
    /// True for the formats that lose information (Vorbis, Opus, MP3).
    public let isLossy: Bool
    /// The format code of libsndfile (container and encoding together), to write a file in the same format.
    public let sfFormat: Int32

    public var duration: TimeInterval { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
}

public enum AudioFileError: Error, Equatable {
    /// The file cannot be opened as a sound file; the message is libsndfile's.
    case cannotOpen(String)
    case seekFailed(Int64)
    case readFailed(String)
}

/// What a channel of an impulse response looks like: where it starts, where it ends, how loud it is.
public struct ImpulseAnalysis: Equatable, Sendable {
    /// The highest absolute value of the channel, as a linear amplitude.
    public var peak: Float
    /// The first frame that reaches the level of the attack: what comes before is silence, or noise below that level.
    public var attackFrame: Int
    /// One frame after the last one that reaches the level of the tail: what comes after is below that level.
    public var tailFrame: Int
    /// Frames of the channel.
    public var frames: Int

    public var peakDB: Double { peak > 0 ? 20 * log10(Double(peak)) : -.infinity }
    /// Frames before the attack.
    public var leadingFrames: Int { attackFrame }
    /// Frames after the tail level.
    public var trailingFrames: Int { max(0, frames - tailFrame) }
}

/// A sound file opened with libsndfile, which reads WAV, RF64, W64, AIFF, CAF, FLAC, Ogg Vorbis, Opus and MP3, among others.
/// It is a `SampleSource`, so that `WaveformKit` can read it.
///
/// An instance has one position in the file and is not safe for several threads at once: give each thread a source of its
/// own (open the file again).
public final class AudioFile: SampleSource, @unchecked Sendable {
    public let info: AudioFileInfo
    private var handle: OpaquePointer?

    public var channels: Int { info.channels }
    public var frames: Int64 { info.frames }
    public var sampleRate: Double { info.sampleRate }

    public init(url: URL) throws {
        var raw = SF_INFO()
        guard let opened = sf_open(url.path, Int32(SFM_READ), &raw) else {
            throw AudioFileError.cannotOpen(String(cString: sf_strerror(nil)))
        }
        guard raw.channels >= 1, raw.samplerate > 0 else {
            sf_close(opened)
            throw AudioFileError.cannotOpen("not a sound file")
        }
        handle = opened
        info = Self.describe(raw)
    }

    deinit { if let handle { sf_close(handle) } }

    /// The information of a file, without keeping it open.
    public static func probe(_ url: URL) throws -> AudioFileInfo { try AudioFile(url: url).info }

    public func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        guard let handle else { return 0 }
        let got = Int(sf_readf_float(handle, buffer, sf_count_t(maxFrames)))
        if got == 0, sf_error(handle) != 0 { throw AudioFileError.readFailed(String(cString: sf_strerror(handle))) }
        return got
    }

    public func seek(toFrame frame: Int64) throws {
        guard let handle else { return }
        if sf_seek(handle, sf_count_t(frame), SEEK_SET) < 0 { throw AudioFileError.seekFailed(frame) }
    }

    // MARK: Impulse responses

    /// Reads the whole file once and says, for each channel, its peak, where it starts and where it ends.
    /// - Parameters:
    ///   - attackLevelDB: the level, under the peak, below which the start of a channel is silence.
    ///   - tailLevelDB: the level, under the peak, below which the end of a channel is not worth keeping.
    public func analyzeImpulses(attackLevelDB: Double = -60, tailLevelDB: Double = -90) throws -> [ImpulseAnalysis] {
        try seek(toFrame: 0)
        let n = channels
        let block = 1 << 14
        var buffer = [Float](repeating: 0, count: block * n)
        var peaks = [Float](repeating: 0, count: n)
        // First pass: the peak of every channel.
        var total = 0
        while true {
            let got = try buffer.withUnsafeMutableBufferPointer { try read(into: $0.baseAddress!, maxFrames: block) }
            if got == 0 { break }
            for frame in 0..<got { for c in 0..<n { peaks[c] = max(peaks[c], abs(buffer[frame * n + c])) } }
            total += got
        }
        // Second pass: with the peak known, the first and the last frame that reach each level.
        try seek(toFrame: 0)
        let attack = peaks.map { $0 * Float(pow(10, attackLevelDB / 20)) }
        let tail = peaks.map { $0 * Float(pow(10, tailLevelDB / 20)) }
        var first = [Int?](repeating: nil, count: n)
        var last = [Int](repeating: 0, count: n)
        var position = 0
        while true {
            let got = try buffer.withUnsafeMutableBufferPointer { try read(into: $0.baseAddress!, maxFrames: block) }
            if got == 0 { break }
            for frame in 0..<got {
                for c in 0..<n {
                    let v = abs(buffer[frame * n + c])
                    if first[c] == nil, v >= attack[c], v > 0 { first[c] = position + frame }
                    if v >= tail[c], v > 0 { last[c] = position + frame + 1 }
                }
            }
            position += got
        }
        return (0..<n).map { ImpulseAnalysis(peak: peaks[$0], attackFrame: first[$0] ?? 0, tailFrame: last[$0], frames: total) }
    }

    // MARK: Description

    private static func describe(_ raw: SF_INFO) -> AudioFileInfo {
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
        return AudioFileInfo(channels: Int(raw.channels), sampleRate: Double(raw.samplerate), frames: Int64(raw.frames),
                             container: container.name, fileExtension: container.ext, encoding: encoding.name,
                             bitsPerSample: bits, isLossy: lossy, sfFormat: raw.format)
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

/// The sound files of a configuration, looked at once: what libsndfile says about each is kept as long as the file does
/// not change (its date and its size), so that the matrix can ask as often as it likes.
public final class AudioFileCatalog: @unchecked Sendable {
    private struct Stamp: Equatable { var date: Date?; var size: Int? }
    private struct Entry { var stamp: Stamp; var info: AudioFileInfo?; var analysis: [ImpulseAnalysis]? }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    private func stamp(of path: String) -> Stamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return Stamp(date: attributes?[.modificationDate] as? Date, size: (attributes?[.size] as? NSNumber)?.intValue)
    }

    /// What is known of a file; nil when it is not there or is not a sound file.
    public func info(at path: String) -> AudioFileInfo? {
        let current = stamp(of: path)
        lock.lock()
        if let entry = entries[path], entry.stamp == current { lock.unlock(); return entry.info }
        lock.unlock()
        let info = try? AudioFile.probe(URL(fileURLWithPath: path))
        lock.lock()
        entries[path] = Entry(stamp: current, info: info, analysis: nil)
        lock.unlock()
        return info
    }

    /// The analysis of every channel of an impulse response file (reads the whole file the first time).
    public func analysis(at path: String) -> [ImpulseAnalysis]? {
        let current = stamp(of: path)
        lock.lock()
        if let entry = entries[path], entry.stamp == current, let analysis = entry.analysis { lock.unlock(); return analysis }
        lock.unlock()
        guard let file = try? AudioFile(url: URL(fileURLWithPath: path)), let analysis = try? file.analyzeImpulses() else { return nil }
        lock.lock()
        entries[path] = Entry(stamp: current, info: file.info, analysis: analysis)
        lock.unlock()
        return analysis
    }

    /// Forgets what it knows: one file, or all of them.
    public func forget(_ path: String? = nil) {
        lock.lock()
        if let path { entries[path] = nil } else { entries.removeAll() }
        lock.unlock()
    }
}
