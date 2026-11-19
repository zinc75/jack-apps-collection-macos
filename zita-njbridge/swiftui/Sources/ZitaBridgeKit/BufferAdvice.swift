// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How the margin of the receiver's buffer looks, from the last seconds of it.
public enum MarginAssessment: Equatable, Sendable {
    /// Not enough lines yet to say.
    case unknown
    /// The queue never came close to running dry.
    case comfortable
    /// It came close: a slower network moment would cut the sound.
    case tight
    /// It ran dry in the last seconds.
    case dropping
}

/// What buffer to advise. The numbers come from tests between two Macs over a direct cable (README: with a JACK period of 256
/// the defaults are enough, with 1024 use `--buff 30` or more); the others are an estimate and say so.
public enum BufferAdvice {
    /// The extra buffering, in milliseconds, that is enough at a JACK period of `period` frames.
    public static func recommendedMilliseconds(period: Int) -> Int {
        switch period {
        case ..<1: return 10
        case ...256: return 10
        case ...512: return 20
        case ...1024: return 30
        default:
            // Beyond what was measured: the same growth again for each further 1024 frames, rounded up to 5 ms.
            let extra = Double(period - 1024) / 1024 * 30
            return 30 + Int((extra / 5).rounded(.up)) * 5
        }
    }

    /// The length of the resampler filter that `zita-n2j` takes when it is not told (the formula of its source): longer when the
    /// lower of the two rates is close to 44.1 kHz, never below 16.
    public static func automaticFilterDelay(localRate: Int, senderRate: Int) -> Int {
        let k = Double(max(min(localRate, senderRate), 44100))
        return max(16, Int((6.7 * k) / (k - 38000)))
    }

    /// Whether the advice rests on a measure (periods 128 to 1024) or only on an estimate.
    public static func isMeasured(period: Int) -> Bool { (1...1024).contains(period) }

    /// The state of the margin from its last values (in milliseconds, four a second): about the last ten seconds.
    public static func assess(history: [Double], window: Int = 40, minimumLines: Int = 8) -> MarginAssessment {
        let recent = history.suffix(window)
        guard recent.count >= minimumLines, let lowest = recent.min() else { return .unknown }
        if lowest <= 0 { return .dropping }
        if lowest < 1.0 { return .tight }
        return .comfortable
    }

    /// The buffer to suggest, or nil when nothing needs to change: only while the margin is not comfortable, and only when
    /// the buffer is below what the period asks for.
    public static func suggestion(period: Int?, buffer: Int, assessment: MarginAssessment) -> Int? {
        guard let period, assessment == .tight || assessment == .dropping else { return nil }
        let advised = recommendedMilliseconds(period: period)
        return buffer < advised ? advised : nil
    }
}
