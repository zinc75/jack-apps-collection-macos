// SPDX-License-Identifier: MIT

import Accelerate
import Foundation

/// Builds `WaveformPeaks` from the samples of a file given block after block, whatever their size. It knows nothing
/// about file formats: whoever reads the file gives it the samples.
///
/// The file is cut into at most `columns` slices of the same number of frames. A short file gets one column per
/// frame. If the file turns out longer than announced, the extra frames go into the last column.
///
/// An accumulator can start in the middle of a file (`startFrame`), to read a part of it: the accumulators of the
/// parts of a file are joined with `merged`.
public struct PeakAccumulator: Sendable {
    public let channels: Int
    public let totalFrames: Int64
    public let sampleRate: Double
    /// Frames under each column (the last one may hold fewer).
    public let framesPerColumn: Int64
    public let columns: Int
    /// The frame at which the first block given to `add` starts.
    public let startFrame: Int64

    fileprivate var lows: [[Float]]
    fileprivate var highs: [[Float]]
    private var frameIndex: Int64

    public init(channels: Int, totalFrames: Int64, sampleRate: Double, columns: Int = 4096, startFrame: Int64 = 0) {
        self.channels = max(channels, 1)
        self.totalFrames = max(totalFrames, 0)
        self.sampleRate = sampleRate
        let wanted = Int64(max(columns, 1))
        framesPerColumn = max((self.totalFrames + wanted - 1) / wanted, 1)
        self.columns = Int((self.totalFrames + framesPerColumn - 1) / framesPerColumn)
        self.startFrame = max(startFrame, 0)
        frameIndex = max(startFrame, 0)
        lows = Array(repeating: Array(repeating: .infinity, count: self.columns), count: self.channels)
        highs = Array(repeating: Array(repeating: -.infinity, count: self.columns), count: self.channels)
    }

    /// An empty accumulator with the same channels, columns and length as `other`, starting at `startFrame`.
    public init(like other: PeakAccumulator, startFrame: Int64) {
        channels = other.channels
        totalFrames = other.totalFrames
        sampleRate = other.sampleRate
        framesPerColumn = other.framesPerColumn
        columns = other.columns
        self.startFrame = max(startFrame, 0)
        frameIndex = max(startFrame, 0)
        lows = Array(repeating: Array(repeating: .infinity, count: other.columns), count: other.channels)
        highs = Array(repeating: Array(repeating: -.infinity, count: other.columns), count: other.channels)
    }

    /// Frames given to `add` so far.
    public var framesAdded: Int64 { frameIndex - startFrame }

    /// Adds `frames` frames of interleaved samples (channel 0, channel 1, … for frame 0, then frame 1, …).
    public mutating func add(interleaved samples: UnsafePointer<Float>, frames: Int) {
        for c in 0..<channels {
            addChannel(c, base: samples + c, stride: channels, frames: frames)
        }
        frameIndex += Int64(frames)
    }

    /// Adds `frames` frames given one pointer per channel.
    public mutating func add(planar channelPointers: [UnsafePointer<Float>], frames: Int) {
        guard channelPointers.count >= channels else { return }
        for c in 0..<channels {
            addChannel(c, base: channelPointers[c], stride: 1, frames: frames)
        }
        frameIndex += Int64(frames)
    }

    private mutating func addChannel(_ c: Int, base: UnsafePointer<Float>, stride: Int, frames: Int) {
        guard columns > 0 else { return }
        var done = 0
        while done < frames {
            let at = frameIndex + Int64(done)
            let column = min(Int(at / framesPerColumn), columns - 1)
            let remaining = frames - done
            let room = column == columns - 1 ? remaining : min(remaining, Int(Int64(column + 1) * framesPerColumn - at))
            var lo: Float = 0, hi: Float = 0
            let start = base + done * stride
            vDSP_minv(start, vDSP_Stride(stride), &lo, vDSP_Length(room))
            vDSP_maxv(start, vDSP_Stride(stride), &hi, vDSP_Length(room))
            if lo < lows[c][column] { lows[c][column] = lo }
            if hi > highs[c][column] { highs[c][column] = hi }
            done += room
        }
    }

    /// The peaks of what has been added so far. A column that has not been reached reads 0.
    public var peaks: WaveformPeaks { Self.merged([self]) }

    /// The peaks of several accumulators of the same file (same channels, announced length and columns), each of
    /// which read a part of it.
    public static func merged(_ parts: [PeakAccumulator]) -> WaveformPeaks {
        guard let first = parts.first else {
            return WaveformPeaks(channels: 1, totalFrames: 0, sampleRate: 0, filledFrames: 0, minimums: [[]], maximums: [[]])
        }
        var lows = first.lows, highs = first.highs
        var added = first.framesAdded
        for part in parts.dropFirst() {
            precondition(part.channels == first.channels && part.columns == first.columns && part.totalFrames == first.totalFrames,
                         "accumulators of different files cannot be merged")
            added += part.framesAdded
            for c in 0..<first.channels {
                for k in 0..<first.columns {
                    if part.lows[c][k] < lows[c][k] { lows[c][k] = part.lows[c][k] }
                    if part.highs[c][k] > highs[c][k] { highs[c][k] = part.highs[c][k] }
                }
            }
        }
        var read = [Bool](repeating: false, count: first.columns)
        for c in 0..<first.channels {
            for k in 0..<first.columns where lows[c][k] != .infinity { read[k] = true }
        }
        return WaveformPeaks(channels: first.channels, totalFrames: first.totalFrames, sampleRate: first.sampleRate,
                             filledFrames: min(added, first.totalFrames),
                             minimums: lows.map { $0.map { $0 == .infinity ? 0 : $0 } },
                             maximums: highs.map { $0.map { $0 == -.infinity ? 0 : $0 } },
                             columnsRead: read)
    }
}
