// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class AudioFileTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jconvolver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// An impulse response: `lead` frames of silence, a peak of 1, then a decay with the given time constant.
    private func decay(lead: Int, frames: Int, constant: Double = 600) -> [Float] {
        (0..<frames).map { $0 < lead ? 0 : Float(exp(-Double($0 - lead) / constant)) }
    }

    // MARK: What the file says

    func testInfoOfAFloatFile() throws {
        let url = try directory().appendingPathComponent("a.wav")
        try WAVSupport.write(url, channels: 2, rate: 44100, samples: [Float](repeating: 0.1, count: 2 * 1000))
        let info = try AudioFile.probe(url)
        XCTAssertEqual(info.channels, 2)
        XCTAssertEqual(info.sampleRate, 44100)
        XCTAssertEqual(info.frames, 1000)
        XCTAssertEqual(info.bitsPerSample, 32)
        XCTAssertEqual(info.fileExtension, "wav")
        XCTAssertTrue(info.container.contains("WAV"), info.container)
        XCTAssertTrue(info.encoding.lowercased().contains("float"), info.encoding)
        XCTAssertFalse(info.isLossy)
        XCTAssertNotEqual(info.sfFormat, 0)
        XCTAssertEqual(info.duration, 1000.0 / 44100, accuracy: 1e-9)
    }

    func testInfoOfAnIntegerFile() throws {
        let url = try directory().appendingPathComponent("a.wav")
        try WAVSupport.write(url, channels: 1, encoding: .int16, samples: [Float](repeating: 0.1, count: 500))
        let info = try AudioFile.probe(url)
        XCTAssertEqual(info.bitsPerSample, 16)
        XCTAssertTrue(info.encoding.contains("16"), info.encoding)
    }

    func testAFileThatIsNotASoundFileCannotBeOpened() throws {
        let dir = try directory()
        let garbage = dir.appendingPathComponent("g.wav")
        try Data("this is not audio".utf8).write(to: garbage)
        XCTAssertThrowsError(try AudioFile(url: garbage)) {
            if case AudioFileError.cannotOpen = $0 {} else { XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try AudioFile(url: dir.appendingPathComponent("missing.wav")))
    }

    func testReadingAndSeeking() throws {
        let url = try directory().appendingPathComponent("r.wav")
        let ramp = (0..<1000).map { Float($0) / 1000 }
        try WAVSupport.write(url, channels: 1, samples: ramp)
        let file = try AudioFile(url: url)
        var buffer = [Float](repeating: 0, count: 4)
        XCTAssertEqual(try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 4) }, 4)
        XCTAssertEqual(buffer, Array(ramp[0..<4]))
        try file.seek(toFrame: 500)
        XCTAssertEqual(try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 4) }, 4)
        XCTAssertEqual(buffer, Array(ramp[500..<504]))
        try file.seek(toFrame: 998)
        XCTAssertEqual(try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 4) }, 2)
        XCTAssertEqual(try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: 4) }, 0)
    }

    // MARK: Impulse responses

    func testWhereAnImpulseResponseStartsAndEnds() throws {
        let url = try directory().appendingPathComponent("ir.wav")
        try WAVSupport.write(url, channels: 1, samples: decay(lead: 240, frames: 12000))
        let a = try XCTUnwrap(try AudioFile(url: url).analyzeImpulses().first)
        XCTAssertEqual(a.peak, 1, accuracy: 1e-6)
        XCTAssertEqual(a.peakDB, 0, accuracy: 1e-4)
        XCTAssertEqual(a.attackFrame, 240)
        XCTAssertEqual(a.leadingFrames, 240)
        // The decay reaches -90 dB after 600 * ln(10^4.5) = 6216 frames.
        XCTAssertEqual(a.tailFrame, 240 + 6216 + 1, accuracy: 3)
        XCTAssertEqual(a.frames, 12000)
        XCTAssertEqual(a.trailingFrames, 12000 - a.tailFrame)
    }

    func testNoiseBelowTheAttackLevelIsNotTheAttack() throws {
        var samples = decay(lead: 240, frames: 4000)
        for i in 0..<240 { samples[i] = 1e-5 * (i % 2 == 0 ? 1 : -1) }   // -100 dB below the peak
        let url = try directory().appendingPathComponent("ir.wav")
        try WAVSupport.write(url, channels: 1, samples: samples)
        let a = try XCTUnwrap(try AudioFile(url: url).analyzeImpulses().first)
        XCTAssertEqual(a.attackFrame, 240)
        XCTAssertEqual(try XCTUnwrap(try AudioFile(url: url).analyzeImpulses(attackLevelDB: -120).first).attackFrame, 0)
    }

    func testEveryChannelIsAnalysedOnItsOwn() throws {
        let url = try directory().appendingPathComponent("ir.wav")
        let left = decay(lead: 100, frames: 3000, constant: 200)
        let right = decay(lead: 1000, frames: 3000, constant: 200).map { $0 * 0.5 }
        var interleaved: [Float] = []
        for i in 0..<3000 { interleaved += [left[i], right[i]] }
        try WAVSupport.write(url, channels: 2, samples: interleaved)
        let a = try AudioFile(url: url).analyzeImpulses()
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].attackFrame, 100)
        XCTAssertEqual(a[1].attackFrame, 1000)
        XCTAssertEqual(a[1].peak, 0.5, accuracy: 1e-6)
        XCTAssertLessThan(a[0].tailFrame, a[1].tailFrame)
    }

    func testASilentChannel() throws {
        let url = try directory().appendingPathComponent("ir.wav")
        try WAVSupport.write(url, channels: 1, samples: [Float](repeating: 0, count: 500))
        let a = try XCTUnwrap(try AudioFile(url: url).analyzeImpulses().first)
        XCTAssertEqual(a.peak, 0)
        XCTAssertEqual(a.peakDB, -.infinity)
        XCTAssertEqual(a.attackFrame, 0)
        XCTAssertEqual(a.tailFrame, 0)
    }

    func testAFileLongerThanOneBlockIsReadWholeInTwoPasses() throws {
        let url = try directory().appendingPathComponent("long.wav")
        var samples = [Float](repeating: 0, count: 50_000)
        samples[40_000] = 0.25   // beyond the first blocks
        try WAVSupport.write(url, channels: 1, samples: samples)
        let a = try XCTUnwrap(try AudioFile(url: url).analyzeImpulses().first)
        XCTAssertEqual(a.peak, 0.25)
        XCTAssertEqual(a.attackFrame, 40_000)
        XCTAssertEqual(a.tailFrame, 40_001)
    }

    // MARK: The catalog

    func testTheCatalogKeepsWhatItKnowsUntilTheFileChanges() throws {
        let url = try directory().appendingPathComponent("c.wav")
        try WAVSupport.write(url, channels: 1, samples: [Float](repeating: 0.1, count: 100))
        let catalog = AudioFileCatalog()
        XCTAssertEqual(catalog.info(at: url.path)?.frames, 100)
        XCTAssertEqual(catalog.info(at: url.path)?.frames, 100)
        // The same path, another file: its size is not the same.
        try WAVSupport.write(url, channels: 1, samples: [Float](repeating: 0.1, count: 300))
        XCTAssertEqual(catalog.info(at: url.path)?.frames, 300)
    }

    func testTheCatalogDoesNotKnowAFileThatIsNotThere() {
        XCTAssertNil(AudioFileCatalog().info(at: "/nope/missing.wav"))
        XCTAssertNil(AudioFileCatalog().analysis(at: "/nope/missing.wav"))
    }

    func testTheCatalogAnalysesOnceAndForgets() throws {
        let url = try directory().appendingPathComponent("c.wav")
        try WAVSupport.write(url, channels: 1, samples: decay(lead: 50, frames: 2000, constant: 100))
        let catalog = AudioFileCatalog()
        let first = try XCTUnwrap(catalog.analysis(at: url.path))
        XCTAssertEqual(first.first?.attackFrame, 50)
        XCTAssertEqual(catalog.analysis(at: url.path), first)
        XCTAssertEqual(catalog.info(at: url.path)?.frames, 2000)   // the analysis kept the information too
        catalog.forget(url.path)
        XCTAssertEqual(catalog.info(at: url.path)?.frames, 2000)
        catalog.forget()
    }
}
