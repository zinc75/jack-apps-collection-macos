// SPDX-License-Identifier: MIT

import Accelerate
import AVFoundation
import Foundation

/// Something that gives the samples of a file, a block at a time, from the start to the end. The package does not
/// read file formats itself: an application gives it a source (the one below reads what the system reads, and an
/// application can give one that reads more, with libsndfile for instance).
public protocol SampleSource: AnyObject, Sendable {
    var channels: Int { get }
    /// Frames in the file.
    var frames: Int64 { get }
    var sampleRate: Double { get }
    /// Reads up to `maxFrames` frames of interleaved samples into `buffer` (room for `maxFrames * channels` floats) and
    /// returns how many it read, 0 at the end of the file.
    func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int
    /// Moves to a frame, so that the next read starts there. A file is read in several parts at once, each part by
    /// a source of its own, so this has to be cheap and exact.
    func seek(toFrame frame: Int64) throws
}

/// Reads what AVFoundation reads: WAV, AIFF, CAF, FLAC, MP3 and the other formats of the system, not Ogg.
public final class AVFoundationSampleSource: SampleSource, @unchecked Sendable {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer

    public init(url: URL) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 14) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.buffer = buffer
    }

    public var channels: Int { Int(file.processingFormat.channelCount) }
    public var frames: Int64 { file.length }
    public var sampleRate: Double { file.processingFormat.sampleRate }

    public func seek(toFrame frame: Int64) throws {
        file.framePosition = min(max(frame, 0), file.length)
    }

    public func read(into out: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        guard file.framePosition < file.length else { return 0 }
        let wanted = AVAudioFrameCount(min(maxFrames, Int(buffer.frameCapacity)))
        try file.read(into: buffer, frameCount: wanted)
        let got = Int(buffer.frameLength)
        guard got > 0, let data = buffer.floatChannelData else { return 0 }
        let n = channels
        for c in 0..<n {
            let channel = data[c]
            var o = out + c
            for i in 0..<got {
                o.pointee = channel[i]
                o += n
            }
        }
        return got
    }
}

/// Samples held in memory. For tests and previews.
public final class MemorySampleSource: SampleSource, @unchecked Sendable {
    public let channels: Int
    public let sampleRate: Double
    private let samples: [Float]
    private var position = 0

    /// `samples` are interleaved.
    public init(channels: Int, sampleRate: Double, samples: [Float]) {
        self.channels = max(channels, 1)
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var frames: Int64 { Int64(samples.count / channels) }

    public func seek(toFrame frame: Int64) throws {
        position = Int(min(max(frame, 0), frames))
    }

    public func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        let left = samples.count / channels - position
        let n = min(maxFrames, max(left, 0))
        guard n > 0 else { return 0 }
        samples.withUnsafeBufferPointer { src in
            buffer.update(from: src.baseAddress! + position * channels, count: n * channels)
        }
        position += n
        return n
    }
}
