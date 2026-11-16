// SPDX-License-Identifier: GPL-3.0-or-later
//
// The scale and the way the meters settle are those of Jack Capture (GPL-2.0-or-later, which allows this licence), so that
// the meters of the two applications read alike. The scale itself is the one of meterbridge, by Steve Harris.

import Foundation
import MeterKit

/// The meter scale of jack_capture, taken from meterbridge by Steve Harris: a deflection in percent for a level in dB
/// (1 is 0 dBFS, 0.5 is -20 dB). Each piece starts where the one before ends (0, 2.5, 7.5, 15, 30, 50, 100 %). The
/// piece from -60 to -50 dB is written with 5 instead of 2.5 in the console meter of jack_capture, which makes the scale
/// jump there (and fall by 2.5 % at -50 dB); it is continuous here.
public struct IECScale: MeterScale {
    public init() {}

    public func fraction(db: Double) -> Double { Self.fraction(db: db) }

    /// 0...1 for a level in dBFS.
    public static func fraction(db: Double) -> Double {
        let def: Double
        switch db {
        case ..<(-70): def = 0
        case ..<(-60): def = (db + 70) * 0.25
        case ..<(-50): def = (db + 60) * 0.5 + 2.5
        case ..<(-40): def = (db + 50) * 0.75 + 7.5
        case ..<(-30): def = (db + 40) * 1.5 + 15
        case ..<(-20): def = (db + 30) * 2 + 30
        case ..<0: def = (db + 20) * 2.5 + 50
        default: def = 100
        }
        return def / 100
    }
}

/// Turns the peaks the player reports (linear, 1.0 is full scale) into the meters of the display: the level on the scale
/// of the meters, falling a little at a time, the held peak, and the clip mark.
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
