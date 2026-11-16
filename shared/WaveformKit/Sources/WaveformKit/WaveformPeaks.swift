// SPDX-License-Identifier: MIT

import Foundation

/// The shape of a sound file: for each channel, the lowest and the highest sample of each of `columns` slices of
/// the file. 1.0 is full scale, and the values are kept as they are in the file (a floating point file can go
/// beyond 1.0): nothing is normalised, so the levels of the channels stay comparable.
public struct WaveformPeaks: Equatable, Sendable {
    public let channels: Int
    /// Frames of the file, as announced by the file.
    public let totalFrames: Int64
    public let sampleRate: Double
    /// Frames read so far. It grows while the file is being read; peaks are complete when it reaches `totalFrames`.
    public let filledFrames: Int64
    /// `minimums[channel][column]`, 0 for a column that has not been read yet.
    public let minimums: [[Float]]
    /// `maximums[channel][column]`, 0 for a column that has not been read yet.
    public let maximums: [[Float]]
    /// True for each column that has been read, at least in part. While a file is read in several parts at once, the
    /// columns read are not the first ones only.
    public let columnsRead: [Bool]
    /// How many columns have been read.
    public let readColumnCount: Int

    public var columns: Int { minimums.first?.count ?? 0 }

    public var duration: TimeInterval { sampleRate > 0 ? Double(totalFrames) / sampleRate : 0 }

    /// The part of the file that has been read, from 0 to 1.
    public var filledFraction: Double { totalFrames > 0 ? min(Double(filledFrames) / Double(totalFrames), 1) : 0 }

    public var isComplete: Bool { filledFrames >= totalFrames }

    /// - Parameter columnsRead: which columns have been read. By default the first ones, up to `filledFrames`.
    public init(channels: Int, totalFrames: Int64, sampleRate: Double, filledFrames: Int64,
                minimums: [[Float]], maximums: [[Float]], columnsRead: [Bool]? = nil) {
        self.channels = channels
        self.totalFrames = totalFrames
        self.sampleRate = sampleRate
        self.filledFrames = filledFrames
        self.minimums = minimums
        self.maximums = maximums
        let columns = minimums.first?.count ?? 0
        if let columnsRead {
            self.columnsRead = columnsRead
        } else {
            let fraction = totalFrames > 0 ? min(Double(filledFrames) / Double(totalFrames), 1) : 0
            let read = min(Int((Double(columns) * fraction).rounded(.up)), columns)
            self.columnsRead = (0..<columns).map { $0 < read }
        }
        readColumnCount = self.columnsRead.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    /// The highest absolute sample of a channel.
    public func peak(channel: Int) -> Float {
        guard minimums.indices.contains(channel) else { return 0 }
        let low = minimums[channel].min() ?? 0, high = maximums[channel].max() ?? 0
        return max(abs(low), abs(high))
    }

    /// True when a channel goes beyond full scale.
    public func clips(channel: Int) -> Bool { peak(channel: channel) > 1 }

    /// The columns of a channel regrouped into `count` bars, each covering the same share of the file: the lowest
    /// and the highest value under each bar, and whether anything under it has been read. With more bars than
    /// columns, a column is repeated. Columns that have not been read say nothing: they do not pull a bar towards 0.
    public func bars(channel: Int, count: Int) -> (minimums: [Float], maximums: [Float], read: [Bool]) {
        let columns = self.columns
        guard minimums.indices.contains(channel), columns > 0, count > 0 else { return ([], [], []) }
        let low = minimums[channel], high = maximums[channel]
        var lows = [Float](repeating: 0, count: count), highs = [Float](repeating: 0, count: count)
        var reads = [Bool](repeating: false, count: count)
        for i in 0..<count {
            let start = i * columns / count
            let end = min(max((i + 1) * columns / count, start + 1), columns)
            var lo = Float.infinity, hi = -Float.infinity
            for c in start..<end where columnsRead[c] {
                if low[c] < lo { lo = low[c] }
                if high[c] > hi { hi = high[c] }
            }
            if lo <= hi {
                lows[i] = lo
                highs[i] = hi
                reads[i] = true
            }
        }
        return (lows, highs, reads)
    }
}
