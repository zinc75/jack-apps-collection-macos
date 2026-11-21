// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SoundFileKit

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

extension SoundFile {
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
}
