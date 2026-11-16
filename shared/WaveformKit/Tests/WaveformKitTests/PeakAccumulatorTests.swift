// SPDX-License-Identifier: MIT

import XCTest
@testable import WaveformKit

final class PeakAccumulatorTests: XCTestCase {
    private func sine(frames: Int, amplitude: Float, period: Double = 109) -> [Float] {
        (0..<frames).map { amplitude * Float(sin(2 * Double.pi * Double($0) / period)) }
    }

    private func accumulate(_ samples: [Float], channels: Int, columns: Int = 4096, blocks: [Int]) -> WaveformPeaks {
        let total = samples.count / channels
        var accumulator = PeakAccumulator(channels: channels, totalFrames: Int64(total), sampleRate: 48000, columns: columns)
        var done = 0, k = 0
        samples.withUnsafeBufferPointer { p in
            while done < total {
                let n = min(blocks[k % blocks.count], total - done)
                accumulator.add(interleaved: p.baseAddress! + done * channels, frames: n)
                done += n; k += 1
            }
        }
        return accumulator.peaks
    }

    func testTheSineHasThePeakOfItsAmplitude() {
        let peaks = accumulate(sine(frames: 48000, amplitude: 0.5), channels: 1, blocks: [4096])
        XCTAssertEqual(peaks.peak(channel: 0), 0.5, accuracy: 0.01)
        XCTAssertTrue(peaks.isComplete)
        XCTAssertEqual(peaks.duration, 1, accuracy: 1e-9)
        XCTAssertFalse(peaks.clips(channel: 0))
    }

    func testBlocksOfAnySizeGiveTheSamePeaks() {
        var generator = SystemRandomNumberGenerator()
        let samples = (0..<(2 * 10_000)).map { _ in Float.random(in: -1...1, using: &generator) }
        let whole = accumulate(samples, channels: 2, columns: 100, blocks: [10_000])
        for sizes in [[1], [7], [1000, 3, 4096], [33, 999, 1, 5000]] {
            XCTAssertEqual(accumulate(samples, channels: 2, columns: 100, blocks: sizes), whole, "blocks \(sizes)")
        }
    }

    func testAShortFileGetsOneColumnPerFrame() {
        let samples = (0..<300).map { Float($0) / 300 }
        let peaks = accumulate(samples, channels: 1, blocks: [64])
        XCTAssertEqual(peaks.columns, 300)
        XCTAssertEqual(peaks.minimums[0], samples)
        XCTAssertEqual(peaks.maximums[0], samples)
    }

    func testAColumnHoldsItsOwnFrames() {
        let samples = (0..<1000).map { Float($0) }
        let peaks = accumulate(samples, channels: 1, columns: 10, blocks: [37])
        XCTAssertEqual(peaks.columns, 10)
        for k in 0..<10 {
            XCTAssertEqual(peaks.minimums[0][k], Float(k * 100))
            XCTAssertEqual(peaks.maximums[0][k], Float(k * 100 + 99))
        }
    }

    func testTheChannelsKeepTheirOwnLevels() {
        // Three channels at 1, 0.1 and 0: the waveform must show them as they are, not normalised.
        var samples = [Float]()
        for i in 0..<9600 {
            let s = Float(sin(2 * Double.pi * Double(i) / 50))
            samples += [s, 0.1 * s, 0]
        }
        let peaks = accumulate(samples, channels: 3, blocks: [1024])
        XCTAssertEqual(peaks.peak(channel: 0), 1, accuracy: 0.01)
        XCTAssertEqual(peaks.peak(channel: 1), 0.1, accuracy: 0.002)
        XCTAssertEqual(peaks.peak(channel: 2), 0)
    }

    func testInterleavedAndPlanarAgree() {
        let left = sine(frames: 5000, amplitude: 0.7), right = sine(frames: 5000, amplitude: 0.2, period: 31)
        var interleaved = [Float]()
        for i in 0..<5000 { interleaved += [left[i], right[i]] }
        let a = accumulate(interleaved, channels: 2, columns: 64, blocks: [999])
        var planar = PeakAccumulator(channels: 2, totalFrames: 5000, sampleRate: 48000, columns: 64)
        left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in
            planar.add(planar: [l.baseAddress!, r.baseAddress!], frames: 5000)
        } }
        XCTAssertEqual(planar.peaks, a)
    }

    func testTheFramesBeyondTheAnnouncedLengthGoIntoTheLastColumn() {
        var accumulator = PeakAccumulator(channels: 1, totalFrames: 100, sampleRate: 1000, columns: 10)
        let samples = [Float](repeating: 0.1, count: 100) + [0.9, 0.9, 0.9]
        samples.withUnsafeBufferPointer { accumulator.add(interleaved: $0.baseAddress!, frames: 103) }
        let peaks = accumulator.peaks
        XCTAssertEqual(peaks.columns, 10)
        XCTAssertEqual(peaks.maximums[0][9], 0.9)
        XCTAssertEqual(peaks.filledFrames, 100)
    }

    func testWhatWasNotReadYetReadsZero() {
        var accumulator = PeakAccumulator(channels: 1, totalFrames: 1000, sampleRate: 1000, columns: 10)
        let samples = [Float](repeating: 0.5, count: 250)
        samples.withUnsafeBufferPointer { accumulator.add(interleaved: $0.baseAddress!, frames: 250) }
        let peaks = accumulator.peaks
        XCTAssertEqual(peaks.filledFraction, 0.25, accuracy: 1e-12)
        XCTAssertFalse(peaks.isComplete)
        XCTAssertEqual(peaks.maximums[0][0], 0.5)
        XCTAssertEqual(peaks.maximums[0][2], 0.5)   // the third column is half read
        XCTAssertEqual(peaks.maximums[0][3], 0)
    }

    func testAnEmptyFileHasNoColumns() {
        let accumulator = PeakAccumulator(channels: 2, totalFrames: 0, sampleRate: 48000)
        XCTAssertEqual(accumulator.peaks.columns, 0)
        XCTAssertEqual(accumulator.peaks.peak(channel: 0), 0)
    }

    func testBeyondFullScaleIsKept() {
        let peaks = accumulate([0.2, -1.5, 0.3, 1.2], channels: 1, blocks: [4])
        XCTAssertTrue(peaks.clips(channel: 0))
        XCTAssertEqual(peaks.peak(channel: 0), 1.5)
    }
}
