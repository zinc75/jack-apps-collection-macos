// SPDX-License-Identifier: MIT

import Foundation

/// What a plot needs of a long signal: for each column of pixels, the smallest and the largest sample it covers.
public struct Envelope: Sendable, Equatable {
    public var lo: [Float]
    public var hi: [Float]
    /// The columns that cover part of the signal: the others are outside it (before its start or after its end) and hold zeros.
    public var valid: Range<Int>

    public init(columns: Int = 0) {
        lo = [Float](repeating: 0, count: max(0, columns))
        hi = lo
        valid = 0..<0
    }

    public var columns: Int { lo.count }

    /// The same envelope of the magnitude: what a plot in decibels draws. Where a column holds both signs, its smallest
    /// magnitude is zero.
    public func magnitude() -> Envelope {
        var out = self
        for c in 0..<lo.count {
            let a = abs(lo[c]), b = abs(hi[c])
            out.hi[c] = max(a, b)
            out.lo[c] = (lo[c] <= 0 && hi[c] >= 0) ? 0 : min(a, b)
        }
        return out
    }
}

/// A min/max pyramid over the samples of a signal. It is built once (a few milliseconds for a million samples, about
/// 170 ms for fifty million) and then answers "the extremes of each of the 3000 columns of this window" in a few
/// microseconds, whatever the zoom: that is what makes a signal of millions of points plot at the pace of the screen.
///
/// Level k holds the minimum and the maximum of blocks of `blocks[k]` samples: 16 at the first level, then four times more
/// at each of the next. The memory it adds is about a third of the signal. The samples are expected to be finite.
public final class PeakPyramid: PlotSignal, @unchecked Sendable {
    /// The signal itself.
    public let samples: [Float]
    private let blocks: [Int]
    private let mins: [[Float]]
    private let maxs: [[Float]]

    /// Below this many samples per column, a column is read from the samples themselves.
    private static let directLimit = 32.0

    public init(samples: [Float]) {
        self.samples = samples
        let n = samples.count
        var blocks: [Int] = [], mins: [[Float]] = [], maxs: [[Float]] = []
        if n > 0 {
            let count = (n + 15) / 16
            var mn = [Float](repeating: 0, count: count), mx = mn
            samples.withUnsafeBufferPointer { p in
                for i in 0..<count {
                    let a = i * 16
                    if a + 16 <= n {
                        let v = UnsafeRawPointer(p.baseAddress! + a).loadUnaligned(as: SIMD16<Float>.self)
                        mn[i] = v.min(); mx[i] = v.max()
                    } else {
                        var lo = p[a], hi = p[a]
                        for j in a..<n { lo = min(lo, p[j]); hi = max(hi, p[j]) }
                        mn[i] = lo; mx[i] = hi
                    }
                }
            }
            blocks.append(16); mins.append(mn); maxs.append(mx)
            while mins[mins.count - 1].count > 64 {
                let pm = mins[mins.count - 1], px = maxs[maxs.count - 1]
                let c = (pm.count + 3) / 4
                var nm = [Float](repeating: 0, count: c), nx = nm
                for i in 0..<c {
                    let a = i * 4, b = min(a + 4, pm.count)
                    var lo = pm[a], hi = px[a]
                    for j in a..<b { lo = min(lo, pm[j]); hi = max(hi, px[j]) }
                    nm[i] = lo; nx[i] = hi
                }
                blocks.append(blocks[blocks.count - 1] * 4); mins.append(nm); maxs.append(nx)
            }
        }
        self.blocks = blocks
        self.mins = mins
        self.maxs = maxs
    }

    public var count: Int { samples.count }

    public func sample(at index: Int) -> Float { samples[index] }

    /// The extremes of the samples in `range` (clamped to the signal), or nil when it holds none.
    public func extremes(in range: Range<Int>) -> (min: Float, max: Float)? {
        let a = max(0, range.lowerBound), b = min(samples.count, range.upperBound)
        guard a < b else { return nil }
        var lo = samples[a], hi = samples[a]
        for i in a..<b { lo = min(lo, samples[i]); hi = max(hi, samples[i]) }
        return (lo, hi)
    }

    /// The extremes of each column of the window [x0, x1) of the signal, in samples, cut in `columns` columns of the same
    /// width. Column c covers the samples from x0 + c w to x0 + (c + 1) w, both ends included, so that neighbouring columns
    /// share a sample and a line through them has no gap. The window may reach outside the signal.
    public func envelope(from x0: Double, to x1: Double, columns: Int, into e: inout Envelope) {
        let w = max(0, columns)
        if e.lo.count != w { e.lo = [Float](repeating: 0, count: w); e.hi = e.lo }
        e.valid = 0..<0
        let n = samples.count
        guard w > 0, n > 0, x1 > x0, x0.isFinite, x1.isFinite else {
            for c in 0..<w { e.lo[c] = 0; e.hi[c] = 0 }
            return
        }
        let spc = (x1 - x0) / Double(w)
        var first = Int.max, last = -1

        if spc < Self.directLimit {
            samples.withUnsafeBufferPointer { p in
                for c in 0..<w {
                    let s = x0 + Double(c) * spc, t = x0 + Double(c + 1) * spc
                    guard t >= 0, s < Double(n) else { e.lo[c] = 0; e.hi[c] = 0; continue }
                    let a = max(0, min(n - 1, Int(s.rounded(.down))))
                    let b = max(a, min(n - 1, Int(t.rounded(.down))))
                    var l = p[a], h = p[a]
                    var j = a + 1
                    while j <= b { l = min(l, p[j]); h = max(h, p[j]); j += 1 }
                    e.lo[c] = l; e.hi[c] = h
                    first = min(first, c); last = c
                }
            }
        } else {
            var level = 0
            while level + 1 < blocks.count, Double(blocks[level + 1]) <= spc { level += 1 }
            let size = Double(blocks[level])
            mins[level].withUnsafeBufferPointer { pm in
                maxs[level].withUnsafeBufferPointer { px in
                    let top = pm.count - 1
                    for c in 0..<w {
                        let s = x0 + Double(c) * spc, t = x0 + Double(c + 1) * spc
                        guard t >= 0, s < Double(n) else { e.lo[c] = 0; e.hi[c] = 0; continue }
                        let a = max(0, min(top, Int((max(0, s)) / size)))
                        let b = max(a, min(top, Int((max(0, t)) / size)))
                        var l = pm[a], h = px[a]
                        var j = a + 1
                        while j <= b { l = min(l, pm[j]); h = max(h, px[j]); j += 1 }
                        e.lo[c] = l; e.hi[c] = h
                        first = min(first, c); last = c
                    }
                }
            }
        }
        if last >= 0 { e.valid = first..<(last + 1) }
    }

    public func envelope(from x0: Double, to x1: Double, columns: Int) -> Envelope {
        var e = Envelope(columns: columns)
        envelope(from: x0, to: x1, columns: columns, into: &e)
        return e
    }
}
