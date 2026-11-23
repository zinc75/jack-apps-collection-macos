// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How far two frequency responses are from each other: the largest difference of their magnitudes, in decibels, over a band.
public enum SpectrumComparison {
    public struct Deviation: Sendable, Equatable {
        /// The largest difference of magnitude, in decibels (always positive).
        public var decibels: Double
        /// Where it is, in hertz.
        public var hertz: Double
        /// The band that was compared, in hertz.
        public var band: ClosedRange<Double>
    }

    /// The largest difference between `a` and `b` over `band` (by default from 20 Hz to nine tenths of the lowest of the two Nyquist frequencies,
    /// where a response that was converted to another rate is still the same), in bands of a twelfth of an octave, the bands of `difference`: the power of each response is
    /// averaged in a band, as an ear would, because the bins of a noisy response go to zero here and there and their ratio means nothing. Bands where
    /// either response is more than 100 dB under its strongest are left out. nil when there is nothing to compare.
    public static func maxDeviation(_ a: FrequencyResponse, _ b: FrequencyResponse, band: ClosedRange<Double>? = nil) -> Deviation? {
        guard !a.isEmpty, !b.isEmpty, let lastA = a.frequencies.last, let lastB = b.frequencies.last else { return nil }
        let range = band ?? 20...(0.9 * min(lastA, lastB))
        guard range.lowerBound > 0, range.lowerBound < range.upperBound else { return nil }
        let strongestA = (a.magnitudes.max() ?? 0), strongestB = (b.magnitudes.max() ?? 0)
        let floorA = strongestA * strongestA * 1e-10, floorB = strongestB * strongestB * 1e-10
        // The same bands as the curve of the difference: a twelfth of an octave.
        let step = pow(2, 1.0 / 12), half = pow(2, 1.0 / 24)
        var worst = 0.0, at = range.lowerBound, any = false
        var center = range.lowerBound * half
        while center / half < range.upperBound {
            let low = center / half, high = min(center * half, range.upperBound)
            if let powerA = meanPower(a, low, high), let powerB = meanPower(b, low, high), powerA > floorA, powerB > floorB {
                let difference = abs(10 * log10(powerA / powerB))
                any = true
                if difference > worst { worst = difference; at = center }
            }
            center *= step
        }
        return any ? Deviation(decibels: worst, hertz: at, band: range) : nil
    }

    /// The difference of two magnitude spectra, in bands of a twelfth of an octave from the bottom of the band to the top (20 Hz to nine tenths of the
    /// lowest Nyquist frequency by default). The bins of two responses are not at the same frequencies (the rates and the lengths differ), and the fine
    /// structure of a noisy response goes to zero here and there: each response is averaged in power over a band, as for `maxDeviation`, and the
    /// result is the distance between the two magnitudes of a band, as a linear magnitude. Drawn in decibels on the axes of the spectra it shows how
    /// far under them the two are from each other. A band that holds no bin takes the nearest one. Empty when there is nothing to compare.
    public static func difference(_ a: FrequencyResponse, _ b: FrequencyResponse, band: ClosedRange<Double>? = nil) -> (frequencies: [Double], magnitudes: [Double]) {
        guard !a.isEmpty, !b.isEmpty, let lastA = a.frequencies.last, let lastB = b.frequencies.last else { return ([], []) }
        let range = band ?? 20...(0.9 * min(lastA, lastB))
        guard range.lowerBound > 0, range.lowerBound < range.upperBound else { return ([], []) }
        let half = pow(2, 1.0 / 24), step = pow(2, 1.0 / 12)
        var frequencies: [Double] = [], magnitudes: [Double] = []
        var center = range.lowerBound * half
        while center < range.upperBound {
            let low = center / half, high = min(center * half, range.upperBound)
            if let powerA = meanPower(a, low, high) ?? nearestPower(a, center), let powerB = meanPower(b, low, high) ?? nearestPower(b, center) {
                frequencies.append(center)
                magnitudes.append(abs(powerA.squareRoot() - powerB.squareRoot()))
            }
            center *= step
        }
        return (frequencies, magnitudes)
    }

    /// The power of the bin that is the nearest to a frequency.
    private static func nearestPower(_ r: FrequencyResponse, _ f: Double) -> Double? {
        guard r.frequencies.count > 1 else { return nil }
        let spacing = r.frequencies[1] - r.frequencies[0]
        guard spacing > 0 else { return nil }
        let k = min(max(Int((f / spacing).rounded()), 0), r.frequencies.count - 1)
        return r.magnitudes[k] * r.magnitudes[k]
    }

    /// The mean power of a response between two frequencies; nil when no bin falls there.
    private static func meanPower(_ r: FrequencyResponse, _ low: Double, _ high: Double) -> Double? {
        // The frequencies are in order, evenly spaced: the first bin of the band is found by the spacing.
        guard r.frequencies.count > 1 else { return nil }
        let spacing = r.frequencies[1] - r.frequencies[0]
        guard spacing > 0 else { return nil }
        let first = max(Int((low / spacing).rounded(.up)), 0), last = min(Int((high / spacing).rounded(.down)), r.frequencies.count - 1)
        guard first <= last else { return nil }
        var sum = 0.0
        for k in first...last { sum += r.magnitudes[k] * r.magnitudes[k] }
        return sum / Double(last - first + 1)
    }
}
