// SPDX-License-Identifier: GPL-3.0-or-later

import SoundFileKit
import XCTest
@testable import JConvolverKit

final class ImpulseFadeTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testTheWindowRisesAndFallsAndIsOneBetween() {
        let ones = [Float](repeating: 1, count: 100)
        let out = ImpulseFade.apply(to: ones, fadeIn: 10, fadeOut: 20)
        XCTAssertEqual(out[0], Float(0.5 - 0.5 * cos(Double.pi * 0.5 / 10)), accuracy: 1e-6)
        XCTAssertLessThan(out[0], 0.01)
        for n in 1..<10 { XCTAssertGreaterThan(out[n], out[n - 1]) }
        XCTAssertEqual(out[10], 1)
        XCTAssertEqual(out[79], 1)
        XCTAssertEqual(out[80], Float(0.5 - 0.5 * cos(Double.pi * 19.5 / 20)), accuracy: 1e-6)
        for n in 81..<100 { XCTAssertLessThan(out[n], out[n - 1]) }
        XCTAssertLessThan(out[99], 0.01)
    }

    func testNoFadeLeavesTheSamplesAlone() {
        let x: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual(ImpulseFade.apply(to: x, fadeIn: 0, fadeOut: 0), x)
    }

    func testTheTwoLengthsStayInsideTheResponse() {
        XCTAssertEqual(ImpulseFade.clamped(fadeIn: 30, fadeOut: 30, length: 40).fadeIn, 30)
        XCTAssertEqual(ImpulseFade.clamped(fadeIn: 30, fadeOut: 30, length: 40).fadeOut, 10)
        XCTAssertEqual(ImpulseFade.clamped(fadeIn: -5, fadeOut: 3, length: 40).fadeIn, 0)
        XCTAssertEqual(ImpulseFade.clamped(fadeIn: 100, fadeOut: 3, length: 40).fadeIn, 40)
        XCTAssertEqual(ImpulseFade.clamped(fadeIn: 100, fadeOut: 3, length: 40).fadeOut, 0)
    }

    func testThePartThatIsRead() {
        XCTAssertEqual(ImpulseFade.used(offset: 10, length: 0, total: 100), 10..<100)
        XCTAssertEqual(ImpulseFade.used(offset: 10, length: 30, total: 100), 10..<40)
        XCTAssertEqual(ImpulseFade.used(offset: 90, length: 30, total: 100), 90..<100)
        XCTAssertTrue(ImpulseFade.used(offset: 200, length: 0, total: 100).isEmpty)
    }

    func testTheNameSaysWhatWasDone() {
        XCTAssertEqual(ImpulseFade.fileName(original: "/a/b/chapelle.wav", channel: 1, start: 240, length: 91200, fadeIn: 0, fadeOut: 4800, ext: "wav"),
                       "chapelle_ch1_start240_len91200_fadein0_fadeout4800.wav")
    }

    func testTheFolderNameHasNoColon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 32))!
        XCTAssertEqual(ImpulseFade.folderName(for: date, calendar: calendar), "2026-11-21_14-32_IR-fades")
    }

    func testTheFileHoldsOnePartOfOneChannelWithTheFades() throws {
        var stereo: [Float] = []
        for i in 0..<200 { stereo.append(0.5); stereo.append(Float(i) / 1000) }
        let source = folder.appendingPathComponent("two.wav")
        try WAVSupport.write(source, channels: 2, rate: 44100, samples: stereo)
        let before = try Data(contentsOf: source)
        let destination = folder.appendingPathComponent("sub/out.wav")
        let info = try ImpulseFade.write(source: source, channel: 2, offset: 50, length: 100, fadeIn: 10, fadeOut: 20, to: destination)
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.sampleRate, 44100)
        XCTAssertEqual(info.frames, 100)
        let written = try CurveData.load(url: destination, channel: 1).samples
        // Frame 50 of the right channel is 0.05, with the first step of the fade in.
        XCTAssertEqual(written[0], 0.05 * Float(0.5 - 0.5 * cos(Double.pi * 0.5 / 10)), accuracy: 1e-6)
        XCTAssertEqual(written[10], 0.06, accuracy: 1e-6)
        XCTAssertEqual(written[79], 0.129, accuracy: 1e-6)
        XCTAssertLessThan(written[99], 0.001)
        // The original is not touched, and nothing is left beside the new file.
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), ["out.wav"])
    }

    func testTheFormatOfTheSourceIsKept() throws {
        let source = folder.appendingPathComponent("short.wav")
        try WAVSupport.write(source, channels: 1, encoding: .int16, samples: (0..<64).map { Float($0) / 100 })
        let destination = folder.appendingPathComponent("short-fade.wav")
        let info = try ImpulseFade.write(source: source, channel: 1, offset: 0, length: 0, fadeIn: 8, fadeOut: 0, to: destination)
        XCTAssertEqual(info.bitsPerSample, 16)
        XCTAssertFalse(info.isLossy)
        XCTAssertEqual(info.frames, 64)
    }

    func testWhatCannotBeDoneIsRefused() throws {
        let source = folder.appendingPathComponent("a.wav")
        try WAVSupport.write(source, channels: 1, samples: [0.1, 0.2, 0.3, 0.4])
        XCTAssertThrowsError(try ImpulseFade.write(source: source, channel: 2, offset: 0, length: 0, fadeIn: 1, fadeOut: 1, to: folder.appendingPathComponent("x.wav"))) {
            XCTAssertEqual($0 as? ImpulseFadeError, .channelMissing)
        }
        XCTAssertThrowsError(try ImpulseFade.write(source: source, channel: 1, offset: 10, length: 0, fadeIn: 1, fadeOut: 1, to: folder.appendingPathComponent("x.wav"))) {
            XCTAssertEqual($0 as? ImpulseFadeError, .emptyZone)
        }
        // A name that is taken is not overwritten.
        let taken = folder.appendingPathComponent("taken.wav")
        try Data("x".utf8).write(to: taken)
        XCTAssertThrowsError(try ImpulseFade.write(source: source, channel: 1, offset: 0, length: 0, fadeIn: 1, fadeOut: 1, to: taken))
        XCTAssertEqual(try Data(contentsOf: taken), Data("x".utf8))
    }
}
