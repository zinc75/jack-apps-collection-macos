// SPDX-License-Identifier: MIT

import Foundation

/// The width of the band that is averaged around each point of a spectrum, as a fraction of an octave. Acousticians read a spectrum
/// smoothed in 1/3 of an octave or in 1/6, because that is how the ear and the standards add up the energy.
public enum OctaveSmoothing: Int, CaseIterable, Hashable, Sendable {
    case none = 0
    case twentyFourth = 24, twelfth = 12, sixth = 6, third = 3, half = 2, octave = 1

    /// "1/3 octave", "1 octave"; empty for none (the application gives its own word for it).
    public var title: String {
        switch self {
        case .none: return ""
        case .octave: return "1 octave"
        default: return "1/\(rawValue) octave"
        }
    }
}

extension PlotCurve {
    /// The index of the first abscissa above `v`.
    private func upperBound(_ v: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if x[mid] <= v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The magnitudes smoothed over a fraction of an octave: each value becomes the root of the mean of the powers (the squares) of
    /// the points within half the fraction of an octave on each side of its abscissa, so that the energy in a band is what is read.
    /// The mean is taken over the points, which is right for the regular bins of a Fourier transform; the points of a curve that are
    /// not finite are left out of the means and stay as they are; an abscissa that is not positive (the bin at 0 Hz) is not smoothed.
    /// The values must be magnitudes (not decibels), and the abscissas increasing.
    public func smoothed(_ smoothing: OctaveSmoothing) -> PlotCurve {
        guard isMagnitude, smoothing != .none else { return self }
        let n = count
        guard n > 1 else { return self }
        // Running sums of the power and of the number of values, so that the mean of a band costs two reads.
        var power = [Double](repeating: 0, count: n + 1), number = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            let ok = y[i].isFinite
            power[i + 1] = power[i] + (ok ? y[i] * y[i] : 0)
            number[i + 1] = number[i] + (ok ? 1 : 0)
        }
        let half = pow(2, 1 / (2 * Double(smoothing.rawValue)))
        var out = y
        for i in 0..<n where y[i].isFinite && x[i] > 0 {
            let low = lowerBound(x[i] / half), high = upperBound(x[i] * half)
            let k = number[high] - number[low]
            if k > 0 { out[i] = ((power[high] - power[low]) / Double(k)).squareRoot() }
        }
        var copy = self
        copy.y = out
        return copy
    }
}
