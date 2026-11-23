// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import Foundation
import SoundFileKit

public enum ImpulseFadeError: Error, Equatable {
    case cannotRead(String)
    case channelMissing
    case emptyZone
    case cannotWrite(String)
}

/// A fade in and a fade out on an impulse response: a window that rises over the first samples and falls over the last ones (a half cosine each, a Tukey
/// window with two lengths), so that cutting the response, even at a low level, does not end on a step.
///
/// `jconvolver` cannot window a response (a line `/impulse/read` has a gain, a delay, a start and a length), so a fade is applied by writing a new audio
/// file, which the configuration then reads. The original is never touched.
public enum ImpulseFade {
    /// The two lengths kept inside the response: neither is negative and together they are no longer than it is.
    public static func clamped(fadeIn: Int, fadeOut: Int, length: Int) -> (fadeIn: Int, fadeOut: Int) {
        let n = max(length, 0)
        let i = min(max(fadeIn, 0), n)
        let o = min(max(fadeOut, 0), n - i)
        return (i, o)
    }

    /// The window of a response of `count` samples: 1 between the fades, and a half cosine at each end that never quite reaches 0 on the rising side
    /// (the first sample is at half a step), which is what keeps the two lengths exact.
    public static func gain(at n: Int, count: Int, fadeIn: Int, fadeOut: Int) -> Float {
        if fadeIn > 0, n < fadeIn { return Float(0.5 - 0.5 * cos(Double.pi * (Double(n) + 0.5) / Double(fadeIn))) }
        if fadeOut > 0, n >= count - fadeOut { return Float(0.5 - 0.5 * cos(Double.pi * (Double(count - n) - 0.5) / Double(fadeOut))) }
        return 1
    }

    /// The samples with the window applied.
    public static func apply(to samples: [Float], fadeIn: Int, fadeOut: Int) -> [Float] {
        let (i, o) = clamped(fadeIn: fadeIn, fadeOut: fadeOut, length: samples.count)
        guard i > 0 || o > 0 else { return samples }
        var out = samples
        let count = samples.count
        for n in 0..<min(i, count) { out[n] *= gain(at: n, count: count, fadeIn: i, fadeOut: o) }
        if o > 0 { for n in max(count - o, 0)..<count { out[n] *= gain(at: n, count: count, fadeIn: i, fadeOut: o) } }
        return out
    }

    /// The part of a file that is read: from `offset`, `length` frames (0 for all of what is left), inside the `total` frames.
    public static func used(offset: Int, length: Int, total: Int) -> Range<Int> {
        let start = min(max(offset, 0), max(total, 0))
        let end = length > 0 ? min(start + length, total) : total
        return start..<max(end, start)
    }

    /// The name of the file that a fade writes: `<original>_ch<K>_start<S>_len<L>_fadein<N>_fadeout<M>.<ext>`, with the channel of the original, the
    /// start and the length that were read (the length that was really used when the response read the file to its end) and the two fades, in samples.
    public static func fileName(original: String, channel: Int, start: Int, length: Int, fadeIn: Int, fadeOut: Int, ext: String) -> String {
        let base = (original as NSString).deletingPathExtension
        return "\((base as NSString).lastPathComponent)_ch\(channel)_start\(start)_len\(length)_fadein\(fadeIn)_fadeout\(fadeOut).\(ext)"
    }

    /// The folder where the files of one application of a fade are put, next to the original: `<date and time>_IR-fades`, no colon in it.
    public static func folderName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d_%02d-%02d_IR-fades", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// The format of the file written for a source: the same container, depth and rate, on one channel. A format that cannot be written as it is (or
    /// that loses information, like Vorbis) is written as 32 bit floats in a WAV file.
    public static func output(for source: SoundFileInfo) -> (format: Int32, fileExtension: String) {
        var probe = SF_INFO()
        probe.channels = 1
        probe.samplerate = Int32(source.sampleRate.rounded())
        probe.format = source.sfFormat
        if source.sfFormat == 0 || source.isLossy || sf_format_check(&probe) == 0 || source.fileExtension.isEmpty {
            return (Int32(SF_FORMAT_WAV) | Int32(SF_FORMAT_FLOAT), "wav")
        }
        return (source.sfFormat, source.fileExtension)
    }

    /// Writes a new file with one channel of `source`: the part that is read, with the two fades. The folder of `destination` is made when it is not there.
    /// - Returns: what the new file is, as `SoundFile.probe` sees it.
    @discardableResult
    public static func write(source: URL, channel: Int, offset: Int, length: Int, fadeIn: Int, fadeOut: Int, to destination: URL) throws -> SoundFileInfo {
        var info = SF_INFO()
        guard let input = sf_open(source.path, Int32(SFM_READ), &info) else { throw ImpulseFadeError.cannotRead(String(cString: sf_strerror(nil))) }
        defer { sf_close(input) }
        let channels = Int(info.channels), frames = Int(info.frames)
        guard channel >= 1, channel <= channels else { throw ImpulseFadeError.channelMissing }
        let zone = used(offset: offset, length: length, total: frames)
        guard !zone.isEmpty else { throw ImpulseFadeError.emptyZone }

        // Only the part that is read: seek to it and take the channel out of the interleaved frames.
        guard sf_seek(input, sf_count_t(zone.lowerBound), SEEK_SET) >= 0 else { throw ImpulseFadeError.cannotRead("seek") }
        var samples = [Float](repeating: 0, count: zone.count)
        var block = [Float](repeating: 0, count: (1 << 14) * channels)
        var done = 0
        while done < zone.count {
            let want = min(1 << 14, zone.count - done)
            let got = block.withUnsafeMutableBufferPointer { Int(sf_readf_float(input, $0.baseAddress, sf_count_t(want))) }
            guard got > 0 else { throw ImpulseFadeError.cannotRead("short read") }
            for i in 0..<got { samples[done + i] = block[i * channels + channel - 1] }
            done += got
        }
        let windowed = apply(to: samples, fadeIn: fadeIn, fadeOut: fadeOut)

        let sourceInfo = try? SoundFile.probe(source)
        var out = SF_INFO()
        out.channels = 1
        out.samplerate = info.samplerate
        out.format = sourceInfo.map { output(for: $0).format } ?? (Int32(SF_FORMAT_WAV) | Int32(SF_FORMAT_FLOAT))

        let directory = destination.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
            throw ImpulseFadeError.cannotWrite(error.localizedDescription)
        }
        let partial = directory.appendingPathComponent(".fade-\(UUID().uuidString).partial")
        guard let handle = sf_open(partial.path, Int32(SFM_WRITE), &out) else { throw ImpulseFadeError.cannotWrite(String(cString: sf_strerror(nil))) }
        _ = sf_command(handle, Int32(SFC_SET_CLIPPING), nil, Int32(SF_TRUE))
        let written = windowed.withUnsafeBufferPointer { Int(sf_writef_float(handle, $0.baseAddress, sf_count_t(windowed.count))) }
        let status = sf_error(handle)
        let message = String(cString: sf_strerror(handle))
        sf_close(handle)
        guard written == windowed.count, status == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw ImpulseFadeError.cannotWrite(message)
        }
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw ImpulseFadeError.cannotWrite("exists") }
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw ImpulseFadeError.cannotWrite(error.localizedDescription)
        }
        return try SoundFile.probe(destination)
    }
}
