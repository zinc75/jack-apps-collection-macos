// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MeterKit

/// Turns the peaks measured by the level-meter client (linear, 1.0 is full scale) into the meters of the display: the
/// level on the scale of the meters, falling a little at a time, the held peak, and the clip mark.
public struct LevelTracker {
    public private(set) var meters: [ChannelMeter] = []
    private var holds: [(value: Double, since: Date)] = []

    /// How long a peak stays on the display before it follows the level down.
    public static let holdTime: TimeInterval = 1.5

    public init() {}

    public mutating func reset() {
        meters = []
        holds = []
    }

    /// `peaks`: one per channel, the highest sample since the last call.
    public mutating func update(peaks: [Float], now: Date = Date(), scale: MeterScale = IECScale()) {
        if holds.count != peaks.count { holds = Array(repeating: (0, now), count: peaks.count) }
        var readings: [ChannelMeter] = []
        for (i, peak) in peaks.enumerated() {
            let db = peak > 0 ? 20 * log10(Double(peak)) : -Double.infinity
            let level = scale.fraction(db: db)
            if level >= holds[i].value || now.timeIntervalSince(holds[i].since) > Self.holdTime { holds[i] = (level, now) }
            readings.append(ChannelMeter(level: level, peak: holds[i].value, clipped: peak >= 1))
        }
        meters = meters.following(readings)
    }
}
