// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import WaveformKit
import XCTest
@testable import JackPlayKit

/// Small sound files for the tests, written with libsndfile itself, in a folder that is removed at the end.
final class TestFiles {
    struct Format {
        let name: String
        let code: Int32
        let lossy: Bool
        let sampleRate: Int32
    }

    static let all: [Format] = [
        Format(name: "wav16", code: Int32(SF_FORMAT_WAV | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "wav24", code: Int32(SF_FORMAT_WAV | SF_FORMAT_PCM_24), lossy: false, sampleRate: 44100),
        Format(name: "wavf", code: Int32(SF_FORMAT_WAV | SF_FORMAT_FLOAT), lossy: false, sampleRate: 96000),
        Format(name: "rf64", code: Int32(SF_FORMAT_RF64 | SF_FORMAT_PCM_24), lossy: false, sampleRate: 48000),
        Format(name: "w64", code: Int32(SF_FORMAT_W64 | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "aiff", code: Int32(SF_FORMAT_AIFF | SF_FORMAT_PCM_16), lossy: false, sampleRate: 48000),
        Format(name: "caf", code: Int32(SF_FORMAT_CAF | SF_FORMAT_PCM_24), lossy: false, sampleRate: 48000),
        Format(name: "flac", code: Int32(SF_FORMAT_FLAC | SF_FORMAT_PCM_24), lossy: false, sampleRate: 44100),
        Format(name: "vorbis", code: Int32(SF_FORMAT_OGG | SF_FORMAT_VORBIS), lossy: true, sampleRate: 48000),
        Format(name: "opus", code: Int32(SF_FORMAT_OGG | SF_FORMAT_OPUS), lossy: true, sampleRate: 48000),
        Format(name: "mp3", code: Int32(SF_FORMAT_MPEG | SF_FORMAT_MPEG_LAYER_III), lossy: true, sampleRate: 44100),
    ]

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jackplay-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// A sine at 0.5 on the first channel, and at 0.25 on the others, `frames` frames long.
    static func sample(frame: Int, channel: Int, rate: Double) -> Float {
        Float(sin(2 * Double.pi * (440 * Double(channel + 1)) * Double(frame) / rate)) * (channel == 0 ? 0.5 : 0.25)
    }

    @discardableResult
    func write(_ format: Format, channels: Int = 2, frames: Int = 24000) throws -> URL {
        let url = directory.appendingPathComponent("\(format.name)-\(channels)ch.\(UUID().uuidString.prefix(4))")
        var info = SF_INFO(frames: 0, samplerate: format.sampleRate, channels: Int32(channels), format: format.code, sections: 0, seekable: 0)
        guard let file = sf_open(url.path, Int32(SFM_WRITE), &info) else {
            throw XCTSkip("this build of libsndfile cannot write \(format.name): \(String(cString: sf_strerror(nil)))")
        }
        var samples = [Float](repeating: 0, count: frames * channels)
        for f in 0..<frames { for c in 0..<channels { samples[f * channels + c] = Self.sample(frame: f, channel: c, rate: Double(format.sampleRate)) } }
        sf_writef_float(file, samples, sf_count_t(frames))
        sf_close(file)
        return url
    }
}

final class SoundFileTests: XCTestCase {
    func testEveryFormatIsReadWithItsFacts() throws {
        let files = try TestFiles()
        for format in TestFiles.all {
            let url = try files.write(format)
            let file = try SoundFile(url: url)
            XCTAssertEqual(file.info.channels, 2, format.name)
            XCTAssertEqual(file.info.sampleRate, Double(format.sampleRate), format.name)
            XCTAssertEqual(file.info.isLossy, format.lossy, format.name)
            if format.lossy {
                XCTAssertEqual(Double(file.info.frames), 24000, accuracy: 3000, format.name)   // the length of a lossy file is approximate
            } else {
                XCTAssertEqual(file.info.frames, 24000, format.name)
            }
            XCTAssertFalse(file.info.container.isEmpty, format.name)
            XCTAssertFalse(file.info.encoding.isEmpty, format.name)
        }
    }

    func testTheNamesAndBitsOfCommonFormats() throws {
        let files = try TestFiles()
        let wav = try SoundFile.probe(files.write(TestFiles.all[1]))
        XCTAssertEqual(wav.container, "WAV (Microsoft)")
        XCTAssertEqual(wav.fileExtension, "wav")
        XCTAssertEqual(wav.encoding, "Signed 24 bit PCM")
        XCTAssertEqual(wav.bitsPerSample, 24)
        XCTAssertEqual(try SoundFile.probe(files.write(TestFiles.all[2])).bitsPerSample, 32)
        let flac = try SoundFile.probe(files.write(TestFiles.all[7]))
        XCTAssertEqual(flac.fileExtension, "flac")
        XCTAssertEqual(flac.bitsPerSample, 24)
        let vorbis = try SoundFile.probe(files.write(TestFiles.all[8]))
        XCTAssertEqual(vorbis.encoding, "Vorbis")
        XCTAssertNil(vorbis.bitsPerSample)
        XCTAssertEqual(vorbis.fileExtension, "oga")   // libsndfile's name for the Ogg container
        XCTAssertEqual(try SoundFile.probe(files.write(TestFiles.all[9])).encoding, "Opus")
    }

    func testTheDurationFollowsTheFramesAndTheRate() throws {
        let files = try TestFiles()
        let info = try SoundFile.probe(files.write(TestFiles.all[1], frames: 44100 * 3))
        XCTAssertEqual(info.duration, 3, accuracy: 1e-9)
    }

    func testTheChannelsAreKept() throws {
        let files = try TestFiles()
        for channels in [1, 2, 6, 9] {
            let info = try SoundFile.probe(files.write(TestFiles.all[0], channels: channels, frames: 2000))
            XCTAssertEqual(info.channels, channels)
        }
        // MP3 and Opus have their own limits (two channels for MP3), Vorbis and FLAC take many.
        XCTAssertEqual(try SoundFile.probe(files.write(TestFiles.all[7], channels: 8, frames: 2000)).channels, 8)
        XCTAssertEqual(try SoundFile.probe(files.write(TestFiles.all[8], channels: 6, frames: 4000)).channels, 6)
    }

    func testTheSamplesAreRead() throws {
        let files = try TestFiles()
        for format in TestFiles.all {
            let file = try SoundFile(url: files.write(format))
            let rate = Double(format.sampleRate)
            var buffer = [Float](repeating: 0, count: 4000 * 2)
            let got = try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 4000) }
            XCTAssertEqual(got, 4000, format.name)
            // The first channel is twice as loud as the second one: the levels of the channels are kept.
            let peak0 = stride(from: 0, to: got * 2, by: 2).map { abs(buffer[$0]) }.max()!
            let peak1 = stride(from: 1, to: got * 2, by: 2).map { abs(buffer[$0]) }.max()!
            XCTAssertEqual(peak0, 0.5, accuracy: format.lossy ? 0.1 : 0.001, format.name)
            XCTAssertEqual(peak1, 0.25, accuracy: format.lossy ? 0.1 : 0.001, format.name)
            if !format.lossy {
                for f in [0, 1, 777, 3999] {
                    XCTAssertEqual(buffer[f * 2], TestFiles.sample(frame: f, channel: 0, rate: rate), accuracy: 1e-3, "\(format.name) frame \(f)")
                }
            }
        }
    }

    func testReadingStopsAtTheEnd() throws {
        let files = try TestFiles()
        let file = try SoundFile(url: files.write(TestFiles.all[0], frames: 1000))
        var buffer = [Float](repeating: 0, count: 600 * 2)
        let counts = try (0..<3).map { _ in try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 600) } }
        XCTAssertEqual(counts, [600, 400, 0])
    }

    func testASeekIsExactForTheLosslessFormats() throws {
        let files = try TestFiles()
        for format in TestFiles.all where !format.lossy {
            let url = try files.write(format)
            let whole = try SoundFile(url: url)
            var all = [Float](repeating: 0, count: 24000 * 2)
            _ = try all.withUnsafeMutableBufferPointer { try whole.read(into: $0.baseAddress!, maxFrames: 24000) }
            let other = try SoundFile(url: url)
            try other.seek(toFrame: 13333)
            var part = [Float](repeating: 0, count: 1000 * 2)
            _ = try part.withUnsafeMutableBufferPointer { try other.read(into: $0.baseAddress!, maxFrames: 1000) }
            XCTAssertEqual(part, Array(all[(13333 * 2)..<(14333 * 2)]), format.name)
        }
    }

    func testASeekWorksForTheLossyFormatsToo() throws {
        let files = try TestFiles()
        for format in TestFiles.all where format.lossy && format.name != "mp3" {
            let file = try SoundFile(url: files.write(format))
            try file.seek(toFrame: 12000)
            var part = [Float](repeating: 0, count: 2000 * 2)
            let got = try part.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 2000) }
            XCTAssertEqual(got, 2000, format.name)
            let peak = part.map { abs($0) }.max()!
            XCTAssertEqual(peak, 0.5, accuracy: 0.1, format.name)
        }
    }

    func testAnMP3WithItsHeaderKeepsItsLengthAndSeeksToTheFrame() throws {
        // A sawtooth, whose value says where in the file one is (a sine repeats and cannot tell). libsndfile writes
        // the header that gives the exact length, and then a seek lands within a few frames of what was asked.
        let files = try TestFiles()
        let period = 5000, frames = 44_100 * 10
        let url = files.directory.appendingPathComponent("saw.mp3")
        var info = SF_INFO(frames: 0, samplerate: 44100, channels: 2, format: Int32(SF_FORMAT_MPEG | SF_FORMAT_MPEG_LAYER_III), sections: 0, seekable: 0)
        guard let writer = sf_open(url.path, Int32(SFM_WRITE), &info) else { throw XCTSkip("this libsndfile cannot write MP3") }
        var samples = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames { let v = Float(i % period) / Float(period) * 0.8; samples[i * 2] = v; samples[i * 2 + 1] = v }
        sf_writef_float(writer, samples, sf_count_t(frames))
        sf_close(writer)
        XCTAssertEqual(try SoundFile.probe(url).frames, Int64(frames))
        for target in [20_000, 123_457, 300_001, 440_000] {
            let file = try SoundFile(url: url)
            try file.seek(toFrame: Int64(target))
            var part = [Float](repeating: 0, count: 2000 * 2)
            _ = try part.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 2000) }
            var best = (shift: 0, error: Double.infinity)
            for shift in -2400...2400 {
                var e = 0.0
                for i in stride(from: 0, to: 2000, by: 7) {
                    let expected = Float(((target + shift + i) % period + period) % period) / Float(period) * 0.8
                    let d = Double(part[i * 2] - expected)
                    e += d * d
                }
                if e < best.error { best = (shift, e) }
            }
            XCTAssertLessThanOrEqual(abs(best.shift), 8, "seek to \(target) landed \(best.shift) frames away")
        }
    }

    func testAFileThatCannotBeReadThrows() throws {
        XCTAssertThrowsError(try SoundFile(url: URL(fileURLWithPath: "/nonexistent/none.wav"))) {
            guard case SoundFileError.cannotOpen = $0 else { return XCTFail("wrong error \($0)") }
        }
        let files = try TestFiles()
        let text = files.directory.appendingPathComponent("notes.txt")
        try "this is not a sound file".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try SoundFile(url: text))
        let empty = files.directory.appendingPathComponent("empty.wav")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        XCTAssertThrowsError(try SoundFile(url: empty))
    }

    func testWaveformKitReadsAFileInSeveralPartsWithLibsndfile() throws {
        let files = try TestFiles()
        for format in TestFiles.all where !format.lossy {
            let url = try files.write(format, channels: 3, frames: 60_000)
            let single = try WaveformLoader.peaks(makeSource: { try SoundFile(url: url) }, workers: 1, columns: 200)
            let parallel = try WaveformLoader.peaks(makeSource: { try SoundFile(url: url) }, workers: 4, columns: 200)
            XCTAssertEqual(parallel, single, format.name)
            XCTAssertTrue(single.isComplete, format.name)
            XCTAssertEqual(single.peak(channel: 0), 0.5, accuracy: 0.01, format.name)
            XCTAssertEqual(single.peak(channel: 1), 0.25, accuracy: 0.01, format.name)
        }
    }

    func testWaveformKitReadsAnOggFile() throws {
        let files = try TestFiles()
        let url = try files.write(TestFiles.all[8], channels: 2, frames: 48000)
        let peaks = try WaveformLoader.peaks(makeSource: { try SoundFile(url: url) }, workers: 1)
        XCTAssertGreaterThan(peaks.filledFraction, 0.9)
        XCTAssertEqual(peaks.peak(channel: 0), 0.5, accuracy: 0.1)
    }
}
