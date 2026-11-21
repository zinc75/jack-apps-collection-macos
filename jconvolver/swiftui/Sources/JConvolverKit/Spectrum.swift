// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import Foundation

/// The magnitude spectrum of an impulse response (or of the part of it the engine reads), for a plot with a logarithmic frequency axis.
public struct Spectrum: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var frequency: Double
        public var decibels: Double
    }

    public let points: [Point]

    /// - Parameters:
    ///   - samples: the impulse response.
    ///   - range: the frames to look at (clamped to the samples).
    ///   - fractionOfOctave: the smoothing, in the width of the band that is averaged around each point (power averaging).
    ///   - count: the number of points, spaced evenly in log frequency from `lowest` to the Nyquist frequency (or `highest`).
    public init(samples: [Float], range: Range<Int>? = nil, sampleRate: Double, fractionOfOctave: Double = 6,
                count: Int = 480, lowest: Double = 20, highest: Double = 24000) {
        let lo = max(range?.lowerBound ?? 0, 0), hi = min(range?.upperBound ?? samples.count, samples.count)
        guard hi - lo >= 2, sampleRate > 0 else { points = []; return }
        let length = hi - lo
        var size = 1024
        while size < length * 2, size < (1 << 21) { size <<= 1 }
        var padded = [Float](repeating: 0, count: size)
        for i in 0..<min(length, size) { padded[i] = samples[lo + i] }

        let power = Self.powerSpectrum(padded)
        let binWidth = sampleRate / Double(size)
        let top = min(highest, sampleRate / 2)
        guard top > lowest, count > 1 else { points = []; return }
        let ratio = pow(top / lowest, 1 / Double(count - 1))
        let half = pow(2, 1 / (2 * max(fractionOfOctave, 1)))
        var out: [Point] = []
        out.reserveCapacity(count)
        // A running sum of the power, so that the average of a band costs two reads.
        var cumulative = [Double](repeating: 0, count: power.count + 1)
        for i in 0..<power.count { cumulative[i + 1] = cumulative[i] + Double(power[i]) }
        for k in 0..<count {
            let f = lowest * pow(ratio, Double(k))
            let a = max(Int((f / half / binWidth).rounded(.up)), 0), b = min(Int((f * half / binWidth).rounded(.down)), power.count - 1)
            let mean: Double
            if b >= a {
                mean = (cumulative[b + 1] - cumulative[a]) / Double(b - a + 1)
            } else {
                mean = Double(power[min(max(Int((f / binWidth).rounded()), 0), power.count - 1)])
            }
            out.append(Point(frequency: f, decibels: 10 * log10(max(mean, 1e-30))))
        }
        points = out
    }

    /// The highest level, in dB.
    public var peakDecibels: Double { points.map(\.decibels).max() ?? -.infinity }

    /// The power in each bin from 0 to the Nyquist frequency, of a block whose length is a power of 2.
    static func powerSpectrum(_ input: [Float]) -> [Float] {
        let n = input.count
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: n / 2), imaginary = real
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                input.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // The first element packs the DC value (real) and the Nyquist value (imaginary): keep the DC one alone.
                i[0] = 0
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        // vDSP's real transform is scaled by 2: bring the magnitudes back to those of the plain transform. The DC and Nyquist values
        // are packed in the first element; keep the DC one.
        var scale = Float(0.25)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(n / 2))
        return power
    }
}
