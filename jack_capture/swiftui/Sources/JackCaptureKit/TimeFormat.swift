// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

public enum TimeFormat {
    /// "hh:mm:ss" for a duration in seconds, rounded down.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// The tenth of a second, as a single digit.
    public static func tenth(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds * 10).rounded(.down))) % 10
    }
}
