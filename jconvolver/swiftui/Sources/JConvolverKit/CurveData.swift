// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SoundFileKit

/// The samples of one channel of an impulse response, all in memory (an impulse response is short: a few megabytes at most), and what a
/// curve drawn from them needs.
public struct CurveData: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Reads a channel (from 1, as in the files) of a sound file.
    public static func load(url: URL, channel: Int) throws -> CurveData {
        let file = try SoundFile(url: url)
        let channels = file.channels
        guard channel >= 1, channel <= channels else { throw SoundFileError.cannotOpen("channel \(channel)") }
        var out = [Float]()
        out.reserveCapacity(Int(file.frames))
        let block = 1 << 14
        var buffer = [Float](repeating: 0, count: block * channels)
        while true {
            let got = try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: block) }
            if got == 0 { break }
            for i in 0..<got { out.append(buffer[i * channels + channel - 1]) }
        }
        return CurveData(samples: out, sampleRate: file.sampleRate)
    }

    public var count: Int { samples.count }
    public var peak: Float { samples.reduce(0) { max($0, abs($1)) } }

    /// For each of `width` columns that share the frames from `start` (included) to `end` (excluded): the lowest and the highest sample. No
    /// smoothing and no averaging: a peak is never lost. A column that falls between two samples (the view is zoomed in) repeats the
    /// nearest ones, so that the curve stays continuous.
    public func columns(from start: Double, to end: Double, width: Int) -> (minimums: [Float], maximums: [Float]) {
        guard width > 0, !samples.isEmpty, end > start else { return ([], []) }
        var lows = [Float](repeating: 0, count: width), highs = lows
        let perColumn = (end - start) / Double(width)
        for c in 0..<width {
            let a = start + Double(c) * perColumn, b = a + perColumn
            var first = Int(a.rounded(.down)), last = Int(b.rounded(.up)) - 1
            first = min(max(first, 0), samples.count - 1)
            last = min(max(last, first), samples.count - 1)
            var lo = samples[first], hi = lo
            if last > first { for i in first...last { let v = samples[i]; lo = min(lo, v); hi = max(hi, v) } }
            lows[c] = lo
            highs[c] = hi
        }
        return (lows, highs)
    }
}

/// How an amplitude becomes a height, from -1 to 1: in a straight line, or in decibels, which shows the tail of the response.
public enum CurveScale: Sendable, Equatable {
    case linear
    /// From `floorDB` (the bottom, for instance -90) up to 0 dB at the peak.
    case decibels(floorDB: Double)

    /// `value` is an amplitude, `reference` the amplitude that fills the view (the peak).
    public func height(of value: Float, reference: Float) -> Double {
        let r = Double(max(reference, 1e-12)), v = Double(value)
        switch self {
        case .linear:
            return max(-1, min(1, v / r))
        case .decibels(let floorDB):
            let a = abs(v)
            guard a > 0 else { return 0 }
            let db = 20 * log10(a / r)
            let h = max(0, (db - floorDB) / -floorDB)
            return v < 0 ? -min(h, 1) : min(h, 1)
        }
    }
}
