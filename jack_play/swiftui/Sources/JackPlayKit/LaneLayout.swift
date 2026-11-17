// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// How the lanes of a file are laid out. One or two channels get 60 points a lane, and from 3 the lanes are never thinner than 45
/// points. The lanes go in columns (each with its own ruler) so that the waveform stays within the height of a window: about
/// 12 lanes to a column, in 4 columns at most (beyond 48 channels the columns are longer, and the page scrolls).
public struct LaneLayout: Equatable, Sendable {
    public let channels: Int

    public init(channels: Int) { self.channels = max(channels, 1) }

    /// The lanes in a column, as far as the number of columns allows.
    static let lanesPerFullColumn = 12, maxColumns = 4

    public var columns: Int { channels <= Self.lanesPerFullColumn ? 1 : min((channels + Self.lanesPerFullColumn - 1) / Self.lanesPerFullColumn, Self.maxColumns) }

    public var laneHeight: CGFloat { channels <= 2 ? 60 : 45 }

    public var lanesPerColumn: Int { (channels + columns - 1) / columns }

    /// The channels of a column, in order: with 64 channels, 1...16 in the first column and 49...64 in the last.
    public func range(_ column: Int) -> Range<Int> {
        let start = min(column * lanesPerColumn, channels)
        return start..<min(start + lanesPerColumn, channels)
    }

    /// The height of the waveform: the lanes of the longest column.
    public var height: CGFloat { CGFloat(lanesPerColumn) * laneHeight }
}
