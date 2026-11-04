// SPDX-License-Identifier: GPL-2.0-or-later

import Accelerate
import AVFoundation
import Foundation

/// What `sndfile-info` says about a sound file, in words a person reads: the container, the encoding, the
/// endianness, the sample rate, the channels, the frames, the bit rate. The container is told by the first bytes
/// of the file; the rest by the system when it can read the file (WAV, RF64, AIFF, CAF, FLAC, MP3; not Ogg).
public struct SoundFileInfo: Equatable, Sendable {
    public enum Encoding: Equatable, Sendable {
        case pcmSigned(bits: Int)
        case pcmUnsigned(bits: Int)
        case float(bits: Int)
        case flac(bits: Int?)
        case vorbis, opus, mpeg

        /// The name `sndfile-info` gives it.
        public var sndfileName: String {
            switch self {
            case .pcmSigned(let bits): return "Signed \(bits) bit PCM"
            case .pcmUnsigned(let bits): return "Unsigned \(bits) bit PCM"
            case .float(let bits): return "\(bits) bit float"
            case .flac(let bits): return bits.map { "FLAC \($0) bit" } ?? "FLAC"
            case .vorbis: return "Vorbis"
            case .opus: return "Opus"
            case .mpeg: return "MPEG Layer III"
            }
        }
    }

    public var container: String
    public var encoding: Encoding?
    /// "Little endian" or "Big endian", for the formats that have one.
    public var endianness: String?
    public var sampleRate: Double?
    public var channels: Int?
    public var frames: Int64?
    public var bytes: Int64

    public var duration: TimeInterval? {
        guard let sampleRate, sampleRate > 0, let frames else { return nil }
        return Double(frames) / sampleRate
    }

    /// Kilobits per second, over the whole file.
    public var bitRate: Double? {
        guard let duration, duration > 0 else { return nil }
        return Double(bytes) * 8 / duration / 1000
    }

    public static func read(_ url: URL) -> SoundFileInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        guard head.count >= 4 else { return nil }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? Int64(head.count)
        let sniffed = sniff(head)
        var info = SoundFileInfo(container: sniffed.container, encoding: sniffed.encoding, endianness: sniffed.endianness, bytes: bytes ?? 0)

        if let file = try? AVAudioFile(forReading: url) {
            let format = file.fileFormat
            info.sampleRate = format.sampleRate
            info.channels = Int(format.channelCount)
            info.frames = file.length
            let settings = format.settings
            let bits = settings[AVLinearPCMBitDepthKey] as? Int
            let isFloat = settings[AVLinearPCMIsFloatKey] as? Bool ?? false
            let formatID = settings[AVFormatIDKey] as? UInt32
            if formatID == kAudioFormatLinearPCM, let bits {
                if isFloat { info.encoding = .float(bits: bits) }
                else if bits == 8 && sniffed.container.hasPrefix("WAV") { info.encoding = .pcmUnsigned(bits: 8) }
                else { info.encoding = .pcmSigned(bits: bits) }
            } else if formatID == kAudioFormatFLAC {
                info.encoding = .flac(bits: bits)
            }
        }
        return info
    }

    /// The container, from the magic numbers at the start of the file.
    static func sniff(_ head: Data) -> (container: String, encoding: Encoding?, endianness: String?) {
        func ascii(_ range: Range<Int>) -> String { String(decoding: head[range.clamped(to: head.startIndex..<head.endIndex)], as: UTF8.self) }
        let little = "Little endian", big = "Big endian"
        switch ascii(0..<4) {
        case "RIFF":
            guard head.count >= 12, ascii(8..<12) == "WAVE" else { return ("RIFF", nil, little) }
            // The format tag of the "fmt " chunk: 0xFFFE says WAVE_FORMAT_EXTENSIBLE (more than 2 channels or 16 bits).
            var offset = 12
            while offset + 10 <= head.count {
                let id = ascii(offset..<offset + 4)
                let size = Int(head[offset + 4]) | Int(head[offset + 5]) << 8 | Int(head[offset + 6]) << 16 | Int(head[offset + 7]) << 24
                if id == "fmt " {
                    let tag = Int(head[offset + 8]) | Int(head[offset + 9]) << 8
                    return (tag == 0xFFFE ? "WAVEX (Microsoft)" : "WAV (Microsoft)", nil, little)
                }
                offset += 8 + size + (size & 1)
            }
            return ("WAV (Microsoft)", nil, little)
        case "RF64": return ("RF64 (EBU)", nil, little)
        case "FORM":
            // AIFF and AIFF-C are one format for libsndfile; the data of the files that jack_capture writes is big endian.
            return ("AIFF (Apple/SGI)", nil, big)
        case "caff": return ("CAF (Apple Core Audio File)", nil, nil)
        case "fLaC": return ("FLAC (FLAC Lossless Audio Codec)", nil, nil)
        case "OggS":
            let text = String(decoding: head.prefix(200), as: UTF8.self)
            let encoding: Encoding? = text.contains("OpusHead") ? .opus : text.contains("vorbis") ? .vorbis : nil
            return ("OGG (OGG Container format)", encoding, nil)
        case "riff": return ("W64 (Sonic Foundry)", nil, little)
        default:
            if ascii(0..<3) == "ID3" || (head[0] == 0xFF && head[1] & 0xE0 == 0xE0) { return ("MPEG (MPEG-1/2 Audio)", .mpeg, nil) }
            return ("Unknown", nil, nil)
        }
    }

    /// The highest absolute sample of each channel, 1.0 being full scale. It reads the whole file: call it
    /// away from the main actor. Nil when the system cannot read the file.
    public static func peaks(of url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 16) else { return nil }
        let channels = Int(file.processingFormat.channelCount)
        var peaks = [Float](repeating: 0, count: channels)
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { return nil }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            for c in 0..<channels {
                var peak: Float = 0
                vDSP_maxmgv(data[c], 1, &peak, vDSP_Length(buffer.frameLength))
                peaks[c] = max(peaks[c], peak)
            }
        }
        return peaks
    }
}
