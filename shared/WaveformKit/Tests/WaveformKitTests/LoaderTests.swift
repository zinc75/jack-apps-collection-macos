// SPDX-License-Identifier: MIT

import AVFoundation
import XCTest
@testable import WaveformKit

final class LoaderTests: XCTestCase {
    private func ramp(frames: Int, channels: Int) -> [Float] {
        (0..<frames).flatMap { i in (0..<channels).map { c in Float(i) / Float(frames) * (c == 0 ? 1 : 0.25) } }
    }

    func testTheLoaderReadsTheWholeSource() throws {
        let source = MemorySampleSource(channels: 2, sampleRate: 48000, samples: ramp(frames: 100_000, channels: 2))
        let peaks = try WaveformLoader.peaks(from: source, columns: 500, blockFrames: 4096)
        XCTAssertTrue(peaks.isComplete)
        XCTAssertEqual(peaks.channels, 2)
        XCTAssertEqual(peaks.columns, 500)
        XCTAssertEqual(peaks.peak(channel: 0), 1, accuracy: 0.001)
        XCTAssertEqual(peaks.peak(channel: 1), 0.25, accuracy: 0.001)
    }

    func testTheLoaderReportsItsProgress() throws {
        let source = TestSource(channels: 1, samples: ramp(frames: 200_000, channels: 1), delay: 0.001)
        var reports = [WaveformPeaks]()
        _ = try WaveformLoader.peaks(from: source, columns: 100, blockFrames: 1024, progressInterval: 0) { reports.append($0) }
        XCTAssertGreaterThan(reports.count, 5)
        XCTAssertEqual(reports.map(\.filledFrames), reports.map(\.filledFrames).sorted())
        XCTAssertLessThan(reports.first!.filledFraction, 0.9)
    }

    func testTheLoaderStopsWhenAsked() {
        let source = TestSource(channels: 1, samples: ramp(frames: 200_000, channels: 1), delay: 0.002)
        var polls = 0
        XCTAssertThrowsError(try WaveformLoader.peaks(from: source, blockFrames: 1000, isCancelled: { polls += 1; return polls > 3 })) {
            XCTAssertTrue($0 is WaveformLoader.Cancelled)
        }
        let reads = source.reads
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(source.reads, reads, "the thread went on reading after the cancellation")
        XCTAssertLessThan(reads, 200)
    }

    func testAFileOfTheSystemIsRead() throws {
        // A 2 s stereo file, 0.8 on the left and 0.2 on the right, written and read back through AVFoundation.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("waveformkit-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
            buffer.frameLength = 96_000
            for i in 0..<96_000 {
                let s = Float(sin(2 * Double.pi * Double(i) / 100))
                buffer.floatChannelData![0][i] = 0.8 * s
                buffer.floatChannelData![1][i] = 0.2 * s
            }
            try file.write(from: buffer)
        }
        let source = try AVFoundationSampleSource(url: url)
        XCTAssertEqual(source.channels, 2)
        XCTAssertEqual(source.frames, 96_000)
        XCTAssertEqual(source.sampleRate, 48000)
        let peaks = try WaveformLoader.peaks(from: source)
        XCTAssertTrue(peaks.isComplete)
        XCTAssertEqual(peaks.peak(channel: 0), 0.8, accuracy: 0.002)
        XCTAssertEqual(peaks.peak(channel: 1), 0.2, accuracy: 0.002)
        XCTAssertEqual(peaks.duration, 2, accuracy: 1e-9)
    }

    func testAFileThatDoesNotExistThrows() {
        XCTAssertThrowsError(try AVFoundationSampleSource(url: URL(fileURLWithPath: "/nonexistent/none.wav")))
    }
}
