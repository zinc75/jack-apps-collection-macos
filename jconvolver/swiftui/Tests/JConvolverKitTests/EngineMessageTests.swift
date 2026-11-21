// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class EngineMessageTests: XCTestCase {
    private func kind(_ text: String) -> EngineMessage.Kind { EngineMessage.classify(text).kind }

    // MARK: The messages of the programs, as they are written in their sources

    func testTheProgramEndsOnItsOwn() {
        XCTAssertEqual(kind("CPU overload, exiting."), .stopped(.overload))
        XCTAssertEqual(kind("Jack buffer size change, exiting."), .stopped(.bufferSizeChange))
        XCTAssertEqual(kind("Zombified by Jack, exiting."), .stopped(.zombified))
        XCTAssertEqual(EngineMessage.classify("CPU overload, exiting.").stopReason, .overload)
        XCTAssertEqual(EngineMessage.classify("CPU overload, exiting.").severity, .error)
    }

    func testLateComputationThreads() {
        XCTAssertEqual(kind("Computation threads are late (0001)."), .threadsLate(flags: 1))
        XCTAssertEqual(kind("Computation threads are late (0a00)."), .threadsLate(flags: 0xa00))
        XCTAssertEqual(EngineMessage.classify("Computation threads are late (0001).").severity, .warning)
    }

    func testLatencyCompensation() {
        XCTAssertEqual(kind("Line 4: First 600 frames removed by latency compensation."), .latencyCompensated(line: 4, frames: 600))
        XCTAssertEqual(kind("Line 12: Dirac pulse removed: delay < latency."), .impulseRemoved(line: 12))
        XCTAssertEqual(kind("Line 13: Hilbert impulse removed: delay < latency + lenght / 2."), .impulseRemoved(line: 13))
    }

    func testFilesOfImpulseResponses() {
        XCTAssertEqual(kind("Line 7: Unable to open '/Users/eric/IR/room.wav'."), .fileUnreadable(line: 7, path: "/Users/eric/IR/room.wav"))
        XCTAssertEqual(kind("Line 7: Sample rate (44100) of '/a/b.wav' does not match."), .sampleRateMismatch(line: 7, rate: 44100, path: "/a/b.wav"))
        XCTAssertEqual(kind("Line 8: Data truncated."), .dataTruncated(line: 8))
        XCTAssertEqual(kind("Line 3: partition size adjusted to 512."), .partitionAdjusted(line: 3, size: 512))
    }

    func testOtherRefusalsOfALine() {
        for body in ["Syntax error.", "Bad or missing parameters.", "Unknown command.", "No convolver yet defined.",
                     "Bad input or output number.", "Channel not available.", "Can't seek to offset.", "Error reading file.",
                     "Out of memory.", "Can't change directory to '/nope'.", "Number of inputs (200) is out of range.",
                     "Partition size (100) is illegal.", "Convolver size (999999999) is out of range.", "Density parameter is out of range."] {
            XCTAssertEqual(kind("Line 5: \(body)"), .configError(line: 5, text: body), body)
            XCTAssertEqual(EngineMessage.classify("Line 5: \(body)").severity, .error)
        }
    }

    func testTheProgramCannotStart() {
        for text in ["Can't connect to JACK", "Can't activate JACK.", "Fragment size is too small", "Fragment size is too large",
                     "Zita-convolver does not match compile-time version.", "Can't initialise convolution engine.",
                     "Can't initialise convolution engine", "Can't open '/nope.conf' for reading",
                     "Unable to read input file '/nope.wav'", "Unable to create output file '/nope/out.wav'",
                     "Number of inputs (2) in config file doesn't match input file (1)'"] {
            XCTAssertEqual(kind(text), .cannotStart, text)
        }
    }

    func testAnythingElseIsJustInformation() {
        XCTAssertEqual(kind("something new"), .other)
        XCTAssertEqual(EngineMessage.classify("something new").severity, .info)
    }

    // MARK: The reading of what comes

    func testLinesComeInPiecesOfAnySize() {
        var parser = EngineLogParser()
        XCTAssertTrue(parser.feed(Data("Computation thr".utf8)).isEmpty)
        let first = parser.feed(Data("eads are late (0001).\r\nCPU over".utf8))
        XCTAssertEqual(first.map(\.kind), [.threadsLate(flags: 1)])
        let second = parser.feed(Data("load, exiting.\r\n".utf8))
        XCTAssertEqual(second.map(\.kind), [.stopped(.overload)])
    }

    func testCarriageReturnsAndEmptyLinesAreDropped() {
        var parser = EngineLogParser()
        let out = parser.feed(Data("\r\n\r\nLine 1: Data truncated.\r\n   \r\n".utf8))
        XCTAssertEqual(out.map(\.text), ["Line 1: Data truncated."])
    }

    func testTheLastLineWithoutALineBreakComesWhenTheProgramEnds() {
        var parser = EngineLogParser()
        XCTAssertTrue(parser.feed(Data("Zombified by Jack, exiting.".utf8)).isEmpty)
        XCTAssertEqual(parser.finish().map(\.kind), [.stopped(.zombified)])
        XCTAssertTrue(parser.finish().isEmpty)
    }

    func testSeveralLinesInOneChunk() {
        var parser = EngineLogParser()
        let out = parser.feed(Data("Line 4: First 600 frames removed by latency compensation.\nLine 5: First 600 frames removed by latency compensation.\n".utf8))
        XCTAssertEqual(out.count, 2)
    }

    // MARK: The end of a run

    func testWhatAnEndMeans() {
        typealias T = EngineTermination
        // jconvolver returns 0 after "CPU overload, exiting.": the message is what says it.
        XCTAssertEqual(T.outcome(status: 0, requested: false, stopReason: .overload), .stoppedByEngine(.overload))
        XCTAssertEqual(T.outcome(status: 0, requested: true, stopReason: nil), .stoppedOnRequest)
        XCTAssertEqual(T.outcome(status: 1, requested: true, stopReason: nil), .stoppedOnRequest)   // fconvolver returns 1 when stopped
        XCTAssertEqual(T.outcome(status: 0, requested: false, stopReason: nil), .finished)
        XCTAssertEqual(T.outcome(status: 1, requested: false, stopReason: nil), .failed(status: 1))
        XCTAssertEqual(T.outcome(status: 128 + 11, requested: false, stopReason: nil), .failed(status: 139))
    }
}
