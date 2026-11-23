// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// What is done with the room left on the disk while something is recorded: how long it lasts, when to say that it runs short, and when to stop.
public enum DiskGuard {
    /// The person is told when this little of the recording is left.
    public static let warnSeconds: Double = 15 * 60

    public static func reserveBytes(gigabytes: Int) -> Int64 { Int64(max(0, gigabytes)) * 1_000_000_000 }

    /// Seconds of recording left before the disk gets to the reserve at this rate; nil when nothing is written.
    public static func secondsLeft(free: Int64, reserve: Int64, bytesPerSecond: Double) -> Double? {
        guard bytesPerSecond > 0 else { return nil }
        return Double(max(0, free - reserve)) / bytesPerSecond
    }

    public enum Verdict: Equatable, Sendable {
        case fine
        /// Little time is left: said once.
        case low
        /// The disk is at the reserve: the recording is stopped, its file closed.
        case stop
    }

    public static func verdict(free: Int64, reserve: Int64, bytesPerSecond: Double) -> Verdict {
        if reserve > 0, free <= reserve { return .stop }
        if let left = secondsLeft(free: free, reserve: reserve, bytesPerSecond: bytesPerSecond), left <= warnSeconds { return .low }
        return .fine
    }
}
