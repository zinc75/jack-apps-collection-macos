// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import Foundation

/// The frequency response of an impulse response (or of the part of it the engine reads): magnitude, phase and group delay at each
/// frequency of the transform, from 0 to half the sample rate. The plot smooths the magnitudes in fractions of an octave and draws
/// them on a logarithmic axis; this only computes the transform.
public struct FrequencyResponse: Sendable {
    /// Hertz, from 0 to the Nyquist frequency.
    public let frequencies: [Double]
    /// Linear magnitudes: the gain of the response at each frequency.
    public let magnitudes: [Double]
    /// Degrees, wrapped to ±180.
    public let phases: [Double]
    /// Milliseconds. The exact group delay: the transform of n·h[n] over that of h[n], so there is no phase to unwrap. Not a number
    /// where the response is so low that the quotient means nothing.
    public let groupDelays: [Double]

    public var isEmpty: Bool { frequencies.isEmpty }

    /// - Parameters:
    ///   - samples: the impulse response.
    ///   - range: the frames to look at (clamped to the samples); the delay is counted from its first frame.
    ///   - sizeLimit: the largest transform, in points (a power of two). The block is padded with zeros to twice its length, so that
    ///     the frequencies are closer than the resolution of the block, and cut at this size.
    public init(samples: [Float], range: Range<Int>? = nil, sampleRate: Double, sizeLimit: Int = 1 << 21) {
        let lo = max(range?.lowerBound ?? 0, 0), hi = min(range?.upperBound ?? samples.count, samples.count)
        guard hi - lo >= 2, sampleRate > 0 else {
            frequencies = []; magnitudes = []; phases = []; groupDelays = []
            return
        }
        let length = hi - lo
        var size = 4096
        while size < length * 2, size < sizeLimit { size <<= 1 }
        let used = min(length, size)
        var h = [Double](repeating: 0, count: size), nh = h
        for i in 0..<used {
            let v = Double(samples[lo + i])
            h[i] = v
            nh[i] = v * Double(i)
        }
        guard let (hRe, hIm) = Self.transform(h), let (nRe, nIm) = Self.transform(nh) else {
            frequencies = []; magnitudes = []; phases = []; groupDelays = []
            return
        }
        let half = size / 2
        var f = [Double](), m = [Double](), p = [Double](), g = [Double]()
        f.reserveCapacity(half + 1); m.reserveCapacity(half + 1); p.reserveCapacity(half + 1); g.reserveCapacity(half + 1)
        var strongest = 0.0
        for k in 0...half { strongest = max(strongest, hRe[k] * hRe[k] + hIm[k] * hIm[k]) }
        // Below this power (−140 dB under the strongest bin) the quotient is rounding noise.
        let floor = strongest * 1e-14
        for k in 0...half {
            let power = hRe[k] * hRe[k] + hIm[k] * hIm[k]
            f.append(Double(k) * sampleRate / Double(size))
            m.append(power.squareRoot())
            p.append(atan2(hIm[k], hRe[k]) * 180 / .pi)
            // Re{ N · conj(H) } / |H|² is the delay in samples.
            g.append(power > floor ? (nRe[k] * hRe[k] + nIm[k] * hIm[k]) / power / sampleRate * 1000 : .nan)
        }
        frequencies = f; magnitudes = m; phases = p; groupDelays = g
    }

    /// The bins 0 to size/2 (included) of the transform of a real block, whose length is a power of two.
    private static func transform(_ input: [Double]) -> (re: [Double], im: [Double])? {
        let n = input.count
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetupD(setup) }
        var re = input, im = [Double](repeating: 0, count: n)
        var outRe = [Double](repeating: 0, count: n), outIm = outRe
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                outRe.withUnsafeMutableBufferPointer { orr in
                    outIm.withUnsafeMutableBufferPointer { oi in
                        var source = DSPDoubleSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                        var output = DSPDoubleSplitComplex(realp: orr.baseAddress!, imagp: oi.baseAddress!)
                        vDSP_fft_zopD(setup, &source, 1, &output, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
            }
        }
        return (Array(outRe[0...(n / 2)]), Array(outIm[0...(n / 2)]))
    }
}
