// SPDX-License-Identifier: GPL-3.0-or-later

import SoundFileKit
import XCTest
@testable import JConvolverKit

final class AudioResamplerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("resampler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sine(_ frames: Int, rate: Double, hertz: Double = 440) -> [Float] {
        (0..<frames).map { Float(0.5 * sin(2 * Double.pi * hertz * Double($0) / rate)) }
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func testTheFileIsWrittenNextToTheOriginalAtTheNewRate() throws {
        let source = folder.appendingPathComponent("room.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: sine(22050, rate: 44100))
        let before = try Data(contentsOf: source)
        let result = try AudioResampler.resample(source: source, toRate: 48000)
        XCTAssertFalse(result.reused)
        XCTAssertEqual(result.url.lastPathComponent, "room_resampled_48000.wav")
        XCTAssertEqual(result.info.sampleRate, 48000)
        XCTAssertEqual(result.info.channels, 1)
        // Half a second at 44.1 kHz is 24 000 frames at 48 kHz.
        XCTAssertEqual(Double(result.info.frames), 24000, accuracy: 2)
        // The original is not touched.
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try contents(), ["room.wav", "room_resampled_48000.wav"])
    }

    func testTheSignalStaysWhereItWasInTime() throws {
        // A click at frame 1000 of 44.1 kHz is at 1088.44 of 48 kHz.
        var samples = [Float](repeating: 0, count: 4410)
        samples[1000] = 1
        let source = folder.appendingPathComponent("click.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: samples)
        let result = try AudioResampler.resample(source: source, toRate: 48000)
        let converted = try CurveData.load(url: result.url, channel: 1)
        let peak = converted.samples.enumerated().max { abs($0.element) < abs($1.element) }!.offset
        XCTAssertEqual(Double(peak), 1088.44, accuracy: 1.5)
    }

    func testTheSameConversionIsFoundAndNothingIsWrittenAgain() throws {
        let source = folder.appendingPathComponent("room.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: sine(4410, rate: 44100))
        let first = try AudioResampler.resample(source: source, toRate: 48000)
        let again = try AudioResampler.resample(source: source, toRate: 48000)
        XCTAssertFalse(first.reused)
        XCTAssertTrue(again.reused)
        XCTAssertEqual(again.url, first.url)
        // No second file, and no leftover of the comparison.
        XCTAssertEqual(try contents(), ["room.wav", "room_resampled_48000.wav"])
    }

    func testAFileOfThatNameThatIsNotTheSameIsLeftAloneAndTheNewOneTakesTheNextName() throws {
        let source = folder.appendingPathComponent("room.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: sine(4410, rate: 44100))
        // Something else under the name of the conversion: same rate, other samples.
        let other = folder.appendingPathComponent("room_resampled_48000.wav")
        try WAVSupport.write(other, channels: 1, rate: 48000, samples: sine(4800, rate: 48000, hertz: 1000))
        let before = try Data(contentsOf: other)
        let result = try AudioResampler.resample(source: source, toRate: 48000)
        XCTAssertFalse(result.reused)
        XCTAssertEqual(result.url.lastPathComponent, "room_resampled_48000-2.wav")
        XCTAssertEqual(try Data(contentsOf: other), before)
        // Converting again finds that one, not a third.
        let again = try AudioResampler.resample(source: source, toRate: 48000)
        XCTAssertTrue(again.reused)
        XCTAssertEqual(again.url, result.url)
        XCTAssertEqual(try contents(), ["room.wav", "room_resampled_48000-2.wav", "room_resampled_48000.wav"])
    }

    func testTheGainOfTheFilterIsKept() throws {
        // The coefficients of a filter: the sum of the samples (its gain at zero hertz) does not change with the rate.
        let samples = (0..<2000).map { Float(exp(-Double($0) / 300) * 0.3) }
        let source = folder.appendingPathComponent("tail.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: samples)
        let result = try AudioResampler.resample(source: source, toRate: 48000)
        let converted = try CurveData.load(url: result.url, channel: 1)
        let before = samples.reduce(0) { $0 + Double($1) }, after = converted.samples.reduce(0) { $0 + Double($1) }
        XCTAssertEqual(after / before, 1, accuracy: 0.01)
    }

    func testTheFrequencyResponseDoesNotChangeWithTheConversion() throws {
        // A burst of noise as a filter: its spectrum before and after is the same within a few hundredths of a decibel.
        // The noise is always the same (a small generator of its own), so that the test does not depend on the draw.
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
        let samples = (0..<4000).map { Float(next() * exp(-Double($0) / 600)) }
        let source = folder.appendingPathComponent("noise.wav")
        try WAVSupport.write(source, channels: 1, rate: 44100, samples: samples)
        let result = try AudioResampler.resample(source: source, toRate: 48000)
        let converted = try CurveData.load(url: result.url, channel: 1)
        let a = FrequencyResponse(samples: converted.samples, sampleRate: 48000)
        let b = FrequencyResponse(samples: samples, sampleRate: 44100)
        let deviation = try XCTUnwrap(SpectrumComparison.maxDeviation(a, b, band: 1000...15000))
        XCTAssertLessThan(deviation.decibels, 0.5)
    }

    func testTheFormatOfTheOriginalIsKept() throws {
        let source = folder.appendingPathComponent("pair.wav")
        let left = sine(4410, rate: 44100), right = sine(4410, rate: 44100, hertz: 880)
        try WAVSupport.write(source, channels: 2, rate: 44100, encoding: .int16, samples: zip(left, right).flatMap { [$0, $1] })
        let result = try AudioResampler.resample(source: source, toRate: 96000)
        XCTAssertEqual(result.info.channels, 2)
        XCTAssertEqual(result.info.sampleRate, 96000)
        XCTAssertEqual(result.info.bitsPerSample, 16)
        XCTAssertEqual(result.url.lastPathComponent, "pair_resampled_96000.wav")
    }

    func testAFileAlreadyAtTheRateIsNotConverted() throws {
        let source = folder.appendingPathComponent("room.wav")
        try WAVSupport.write(source, channels: 1, rate: 48000, samples: sine(480, rate: 48000))
        XCTAssertThrowsError(try AudioResampler.resample(source: source, toRate: 48000)) {
            XCTAssertEqual($0 as? AudioResamplerError, .alreadyAtRate)
        }
        XCTAssertEqual(try contents(), ["room.wav"])
    }

    func testAFileThatCannotBeReadIsSaid() {
        XCTAssertThrowsError(try AudioResampler.resample(source: folder.appendingPathComponent("missing.wav"), toRate: 48000)) {
            guard case AudioResamplerError.cannotRead? = $0 as? AudioResamplerError else { return XCTFail("\($0)") }
        }
    }

    func testTheNameOfTheConvertedFile() {
        let source = URL(fileURLWithPath: "/tmp/chapelle.wav")
        XCTAssertEqual(AudioResampler.outputName(for: source, rate: 48000, ext: "wav", attempt: 1), "chapelle_resampled_48000.wav")
        XCTAssertEqual(AudioResampler.outputName(for: source, rate: 48000, ext: "flac", attempt: 3), "chapelle_resampled_48000-3.flac")
    }
}
