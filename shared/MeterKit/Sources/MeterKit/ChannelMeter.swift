// SPDX-License-Identifier: MIT

import Foundation

/// How a level in dBFS is spread over the length of a bar: 0 is the left end, 1 the right end. The scale is
/// the business of each tool (IEC, EBU, linear …): the package only draws what a scale tells it.
public protocol MeterScale: Sendable {
    /// 0...1 for a level in dBFS.
    func fraction(db: Double) -> Double
}

/// One channel of a meter: the level, the peak it holds and whether it clipped.
public struct ChannelMeter: Equatable, Sendable {
    /// 0...1 on the scale in use: 1 is 0 dBFS.
    public var level: Double
    public var peak: Double
    public var clipped: Bool

    public init(level: Double, peak: Double, clipped: Bool) {
        self.level = level
        self.peak = peak
        self.clipped = clipped
    }

    public static let silent = ChannelMeter(level: 0, peak: 0, clipped: false)

    /// How much of its level a meter keeps from one redraw to the next.
    public static let defaultFall = 0.82

    /// The meter as it shows after `new` arrives: the level rises at once and falls a little at a time, as
    /// a needle does; the peak is the one that was measured; the clip mark stays while the peak is still full scale.
    public func following(_ new: ChannelMeter, fall: Double = ChannelMeter.defaultFall) -> ChannelMeter {
        ChannelMeter(level: max(new.level, level * fall), peak: new.peak, clipped: new.clipped || (clipped && new.peak >= 1))
    }
}

public extension Array where Element == ChannelMeter {
    /// The meters of all the channels after a new reading: each follows its own new level. A channel that
    /// had no meter yet takes the new one as it is.
    func following(_ new: [ChannelMeter], fall: Double = ChannelMeter.defaultFall) -> [ChannelMeter] {
        new.enumerated().map { i, reading in i < count ? self[i].following(reading, fall: fall) : reading }
    }
}
