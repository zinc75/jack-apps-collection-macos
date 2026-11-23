// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The zone of a sound file that the engine reads: where it starts and where it ends, in frames, and what the configuration file says of it
/// (an offset and a length). The page of an impulse response and its inspector share these rules.
public enum ImpulseZone {
    /// The zone a start and an end make in a file of `total` frames: inside the file, and at least one frame long.
    public static func clamped(start: Int, end: Int, total: Int) -> (start: Int, end: Int) {
        guard total > 1 else { return (0, max(total - 1, 0)) }
        let s = min(max(start, 0), total - 2)
        let e = min(max(end, s + 1), total - 1)
        return (s, e)
    }

    /// The length the configuration says for a zone that ends at `end`: 0 (to the end of the file) when it ends at the last frame.
    public static func length(start: Int, end: Int, total: Int) -> Int {
        end >= total - 1 ? 0 : max(end - start, 1)
    }
}
