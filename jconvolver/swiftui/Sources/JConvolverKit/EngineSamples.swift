// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An impulse response as the engine has it, from the samples of its file: the part that is read (the start and the length of the .conf file),
/// multiplied by the gain, after as many frames of silence as the delay says. It is what the engine convolves with, so that its spectrum and its phase
/// are the ones of the response in use, and traces of several places of the matrix can be compared as they sound.
public enum EngineSamples {
    public static func make(_ samples: [Float], offset: Int, length: Int, gain: Double, delay: Int) -> [Float] {
        let start = min(max(offset, 0), samples.count)
        let end = length > 0 ? min(start + length, samples.count) : samples.count
        let zone = samples[start..<max(end, start)]
        let g = Float(gain.isFinite ? gain : 0)
        var out = [Float](repeating: 0, count: max(delay, 0))
        out.reserveCapacity(out.count + zone.count)
        for v in zone { out.append(v * g) }
        return out
    }
}
