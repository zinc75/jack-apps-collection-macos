// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ConvValidatorTests: XCTestCase {
    private func pair(_ i: Int, _ o: Int) -> ConvPair { ConvPair(input: i, output: o) }

    private func info(channels: Int = 1, rate: Double = 48000, frames: Int64 = 48000) -> AudioFileInfo {
        AudioFileInfo(channels: channels, sampleRate: rate, frames: frames, container: "WAV", fileExtension: "wav",
                      encoding: "32 bit float", bitsPerSample: 32, isLossy: false, sfFormat: 0x10006)
    }

    /// A context where `room.wav` is a stereo file of one second at 48 kHz and nothing else exists.
    private func context(mode: ConvValidationContext.Mode = .realTime(jackRate: 48000), compensation: Int = 0,
                         files: [String: AudioFileInfo]? = nil) -> ConvValidationContext {
        let known = files ?? ["/ir/room.wav": info(channels: 2)]
        return ConvValidationContext(mode: mode, configDirectory: "/ir", latencyCompensation: compensation, fileInfo: { known[$0] })
    }

    private func file(_ name: String = "room.wav", channel: Int = 1, delay: Int = 0, offset: Int = 0, length: Int = 0) -> ConvImpulse {
        ConvImpulse(source: .file(path: name, channel: channel), delay: delay, offset: offset, length: length)
    }

    private func kinds(_ d: ConvDocument, _ c: ConvValidationContext? = nil) -> [ConvProblem.Kind] {
        ConvValidator.problems(in: d, context: c ?? context()).map(\.kind)
    }

    private func stereo() -> ConvDocument {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(file(channel: 1), at: pair(0, 0))
        d.add(file(channel: 2), at: pair(1, 1))
        return d
    }

    // MARK: Nothing wrong

    func testAMatrixThatIsInOrderHasNoProblem() {
        XCTAssertEqual(kinds(stereo()), [])
    }

    // MARK: The setting

    func testJackThatIsNotRunning() {
        let c = context(mode: .realTime(jackRate: nil))
        XCTAssertEqual(kinds(stereo(), c), [.jackNotRunning])
        XCTAssertEqual(ConvValidator.problems(in: stereo(), context: c).first?.severity, .warning)
    }

    func testTheInputFileOfFconvolverHasToHaveTheChannelsOfTheMatrix() {
        let c = context(mode: .file(input: info(channels: 1)))
        XCTAssertEqual(kinds(stereo(), c), [.inputFileChannels(channels: 1, expected: 2)])
        XCTAssertEqual(kinds(stereo(), context(mode: .file(input: info(channels: 2)))), [])
        XCTAssertEqual(kinds(stereo(), context(mode: .file(input: nil))), [])   // not chosen yet: the interface says so itself
    }

    func testTheRateIsTheOneOfTheInputFileForFconvolver() {
        let c = context(mode: .file(input: info(channels: 2, rate: 44100)))
        XCTAssertEqual(kinds(stereo(), c), [.sampleRateMismatch(path: "/ir/room.wav", fileRate: 48000, expectedRate: 44100)])
    }

    func testLatencyCompensationCountsWhatItCutsOrRemoves() {
        var d = stereo()
        d.add(ConvImpulse(source: .dirac, delay: 10), at: pair(0, 1))
        d.add(file(delay: 700), at: pair(1, 0))
        XCTAssertEqual(kinds(d, context(compensation: 600)), [.latencyAffects(count: 3)])   // two files at delay 0, one pulse
        XCTAssertEqual(kinds(d, context(compensation: 0)), [])
        XCTAssertEqual(kinds(d, context(mode: .file(input: info(channels: 2)), compensation: 600)), [])   // only jconvolver has -L
    }

    // MARK: The ports

    func testTooManyPorts() {
        let d = ConvDocument(inputs: 129, outputs: 2)
        XCTAssertTrue(kinds(d).contains(.tooManyPorts(inputs: 129, outputs: 2, maximum: 128)))
    }

    func testNamesOfPorts() {
        var d = stereo()
        d.inputs[0].name = "Mic"
        d.inputs[1].name = "Mic"
        d.outputs[0].name = "  "
        d.outputs[1].name = "in-1"   // the default name of the first input is "in-1"
        let k = kinds(d)
        XCTAssertTrue(k.contains(.duplicatePortName(isInput: true, name: "Mic", count: 2)))
        XCTAssertTrue(k.contains(.emptyPortName(isInput: false, index: 0)))
        XCTAssertFalse(k.contains { if case .sharedPortName = $0 { return true } else { return false } })   // inputs are named Mic
    }

    func testAnInputAndAnOutputWithTheSameNameAreRefused() {
        var d = stereo()
        d.outputs[1].name = "in-2"   // the default name of the second input
        XCTAssertEqual(kinds(d), [.sharedPortName(name: "in-2")])
    }

    func testPortNamesAreNotCheckedForFconvolver() {
        var d = stereo()
        d.inputs[0].name = "x"
        d.inputs[1].name = "x"
        XCTAssertEqual(kinds(d, context(mode: .file(input: info(channels: 2)))), [])
    }

    // MARK: The matrix

    func testNothingPlaced() {
        XCTAssertEqual(kinds(ConvDocument(inputs: 2, outputs: 2)), [.noImpulse])
    }

    func testAFileThatIsNotThere() {
        var d = ConvDocument(inputs: 1, outputs: 1)
        d.add(file("gone.wav"), at: pair(0, 0))
        let p = ConvValidator.problems(in: d, context: context())
        XCTAssertEqual(p.map(\.kind), [.fileMissing(path: "/ir/gone.wav")])
        XCTAssertEqual(p.first?.pair, pair(0, 0))
        XCTAssertEqual(p.first?.severity, .error)
    }

    func testTheFolderOfAFileIsTheOneOfItsCd() {
        var d = ConvDocument(inputs: 1, outputs: 1)
        var impulse = file("room.wav")
        impulse.directory = "/elsewhere"
        d.add(impulse, at: pair(0, 0))
        XCTAssertEqual(kinds(d), [.fileMissing(path: "/elsewhere/room.wav")])
        var absolute = ConvDocument(inputs: 1, outputs: 1)
        absolute.add(file("/ir/room.wav"), at: pair(0, 0))
        XCTAssertEqual(kinds(absolute), [])
    }

    func testTheRateOfAFileThatIsNotTheOneOfJack() {
        let c = context(files: ["/ir/room.wav": info(channels: 2, rate: 44100)])
        // Reported once for the file, with the first pair that uses it.
        let p = ConvValidator.problems(in: stereo(), context: c)
        XCTAssertEqual(p.map(\.kind), [.sampleRateMismatch(path: "/ir/room.wav", fileRate: 44100, expectedRate: 48000)])
        XCTAssertEqual(p.first?.pair, pair(0, 0))
    }

    func testStartBeyondTheEndAndAChannelThatIsNotThere() {
        var d = ConvDocument(inputs: 1, outputs: 2)
        d.add(file(offset: 48000), at: pair(0, 0))
        d.add(file(channel: 3), at: pair(0, 1))
        XCTAssertEqual(kinds(d), [.startBeyondEnd(offset: 48000, frames: 48000), .channelMissing(channel: 3, channels: 2)])
        var zero = ConvDocument(inputs: 1, outputs: 1)
        zero.add(file(channel: 0), at: pair(0, 0))
        XCTAssertEqual(kinds(zero), [.channelMissing(channel: 0, channels: 2)])
    }

    func testHilbertFilters() {
        var d = ConvDocument(inputs: 1, outputs: 3)
        d.add(ConvImpulse(source: .hilbert(length: 32), delay: 100), at: pair(0, 0))        // too short
        d.add(ConvImpulse(source: .hilbert(length: 1024), delay: 100), at: pair(0, 1))      // delay under half the length
        d.add(ConvImpulse(source: .hilbert(length: 1024), delay: 512), at: pair(0, 2))      // right
        XCTAssertEqual(kinds(d), [.hilbertLengthOutOfRange(length: 32), .hilbertDelayTooSmall(delay: 100, minimum: 512)])
        // With a compensation the delay has to cover it as well.
        XCTAssertEqual(kinds(d, context(compensation: 64)).filter { if case .hilbertDelayTooSmall = $0 { return true } else { return false } }.count, 2)
    }

    func testACopyOfAPairWithNothingOnIt() {
        var d = stereo()
        d.add(ConvImpulse(source: .copy(of: pair(0, 1))), at: pair(1, 0))
        XCTAssertEqual(kinds(d), [.copyOfEmptyPair(source: pair(0, 1))])
        d.add(file(), at: pair(0, 1))
        XCTAssertEqual(kinds(d), [])
    }

    // MARK: The numbers of /convolver/new

    func testPartitionHasToBeAPowerOfTwoWithinLimits() {
        for bad in [0, 32, 100, 16384, 63, 65] {
            var d = stereo()
            d.partition = bad
            XCTAssertEqual(kinds(d), [.partitionIllegal(bad)], "\(bad)")
        }
        for good in [64, 128, 256, 4096, 8192] {
            var d = stereo()
            d.partition = good
            XCTAssertEqual(kinds(d), [], "\(good)")
        }
    }

    func testMaximumLength() {
        var d = stereo()
        d.maxLength = 2_000_000
        XCTAssertEqual(kinds(d), [.maxLengthOutOfRange(2_000_000)])
        d.maxLength = 1000   // the files are 48 000 frames long
        XCTAssertEqual(kinds(d), [.maxLengthTooShort(maxLength: 1000, needed: 48000)])
        d.maxLength = 48000
        XCTAssertEqual(kinds(d), [])
    }

    func testDensity() {
        var d = stereo()
        d.density = 1.5
        XCTAssertEqual(kinds(d), [.densityOutOfRange(1.5)])
        d.density = 0
        XCTAssertEqual(kinds(d), [])
    }

    // MARK: Order

    func testErrorsComeBeforeWarningsAndTheOrderIsKeptWithinEach() {
        var d = ConvDocument(inputs: 1, outputs: 2)
        d.add(file("a-missing.wav"), at: pair(0, 0))
        d.add(file("b-missing.wav"), at: pair(0, 1))
        let p = ConvValidator.problems(in: d, context: context(mode: .realTime(jackRate: nil)))
        XCTAssertEqual(p.map(\.kind), [.fileMissing(path: "/ir/a-missing.wav"), .fileMissing(path: "/ir/b-missing.wav"), .jackNotRunning])
        XCTAssertEqual(p.map(\.severity), [.error, .error, .warning])
    }
}
