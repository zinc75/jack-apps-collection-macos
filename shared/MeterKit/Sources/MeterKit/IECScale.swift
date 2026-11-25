// SPDX-License-Identifier: MIT

import Foundation

/// The deflection scale that JACK meters commonly use, in the spirit of IEC 60268-18: a level in dBFS is
/// mapped to a deflection between 0 and 1 by straight lines between a few breakpoints, so that the low
/// levels are spread out and the top 20 dB take half of the bar (0 dBFS is 1, -20 dB is 0.5, -70 dB and
/// below is 0). The breakpoints are the ones of the scale shared by several JACK meters, written here as
/// a table of numbers.
public struct IECScale: MeterScale {
    public init() {}

    /// Level in dBFS and deflection in percent. The deflection is linear between two neighbours.
    private static let breakpoints: [(db: Double, percent: Double)] = [
        (-70, 0), (-60, 2.5), (-50, 7.5), (-40, 15), (-30, 30), (-20, 50), (0, 100),
    ]

    public func fraction(db: Double) -> Double { Self.fraction(db: db) }

    /// 0...1 for a level in dBFS. A level that is not a number counts as silence.
    public static func fraction(db: Double) -> Double {
        guard db > breakpoints[0].db else { return 0 }
        guard let last = breakpoints.last, db < last.db else { return 1 }
        for i in 1..<breakpoints.count where db < breakpoints[i].db {
            let (d0, p0) = breakpoints[i - 1], (d1, p1) = breakpoints[i]
            return (p0 + (db - d0) * (p1 - p0) / (d1 - d0)) / 100
        }
        return 1
    }
}
