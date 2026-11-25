// SPDX-License-Identifier: GPL-2.0-or-later

import MeterKit
import XCTest
@testable import JackCaptureKit

final class CaptureLogTests: XCTestCase {
    /// Lines as jack_capture 0.9.73 prints them (colours and cursor moves included).
    private let status = "\u{1B}[3A\u{1B}[0m\u{1B}[36m00:|     |\n01:|     |\n\u{1B}[32mBuffer: 3.99s./4.01s    Time: 0.03m.   DHP: [x]  Overruns: 2  Xruns: 5\u{1B}[0m\n"

    func testTheStatusLineIsRead() {
        let events = CaptureLogParser().feedOutput(status)
        XCTAssertEqual(events, [.status(CaptureStatus(bufferFree: 3.99, bufferTotal: 4.01, diskThreadHighPriority: true, overruns: 2, xruns: 5))])
    }

    func testOnlyTheLastStatusOfAChunkCounts() {
        let two = status + status.replacingOccurrences(of: "Xruns: 5", with: "Xruns: 6")
        guard case .status(let s)? = CaptureLogParser().feedOutput(two).last else { return XCTFail("no status") }
        XCTAssertEqual(s.xruns, 6)
    }

    func testAStatusLineSplitBetweenTwoReadsIsStillRead() {
        let parser = CaptureLogParser()
        let cut = status.index(status.startIndex, offsetBy: status.count - 30)
        XCTAssertTrue(parser.feedOutput(String(status[..<cut])).isEmpty)
        XCTAssertEqual(parser.feedOutput(String(status[cut...])).count, 1)
    }

    private func row(_ channel: Int, bar: String, mark: String = "|") -> String {
        String(format: "%02d:|", channel) + bar.padding(toLength: 65, withPad: " ", startingAt: 0) + mark
    }

    func testTheMeterRowsAreRead() {
        // Channel 0: a bar of 20 cells, the held peak at the 30th; channel 1: silent; channel 2: clipped.
        let text = "\u{1B}[3A\u{1B}[36m"
            + row(0, bar: String(repeating: "-", count: 20) + String(repeating: " ", count: 9) + "*") + "\n"
            + row(1, bar: "") + "\n"
            + row(2, bar: String(repeating: "-", count: 65), mark: "!") + "\n"
            + "\u{1B}[32mBuffer: 4.00s./4.01s    Time: 0.00m.   DHP: [ ]  Overruns: 0  Xruns: 0\u{1B}[0m\n"
        let events = CaptureLogParser().feedOutput(text)
        guard case .meters(let m)? = events.first(where: { if case .meters = $0 { return true } else { return false } }) else { return XCTFail("no meters") }
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m[0].level, 20.0 / 65, accuracy: 1e-9)
        XCTAssertEqual(m[0].peak, 30.0 / 65, accuracy: 1e-9)
        XCTAssertFalse(m[0].clipped)
        XCTAssertEqual(m[1], .silent)
        XCTAssertEqual(m[2].level, 1, accuracy: 1e-9)
        XCTAssertTrue(m[2].clipped)
        XCTAssertTrue(events.contains { if case .status = $0 { return true } else { return false } })
    }

    func testTheLastRedrawOfAChunkWins() {
        let two = row(0, bar: String(repeating: "-", count: 5)) + "\n" + row(0, bar: String(repeating: "-", count: 40)) + "\n"
        guard case .meters(let m)? = CaptureLogParser().feedOutput(two).first else { return XCTFail("no meters") }
        XCTAssertEqual(m[0].level, 40.0 / 65, accuracy: 1e-9)
    }

    func testTimemachineWaitingShowsTheLevelAsThePartBeforeTheYellowCode() {
        // jack_capture draws the level with the letters of its message, then goes yellow for the rest.
        let message = "-----------Press <Return> to start recording------------"
        let level = String(message.prefix(14))
        let rest = String(message.dropFirst(14))
        let text = "\u{1B}[36m00:|" + level + "\u{1B}[33m" + rest + "\u{1B}[36m|\n"
        guard case .meters(let m)? = CaptureLogParser().feedOutput(text).first else { return XCTFail("no meters") }
        XCTAssertEqual(m[0].level, 14.0 / 65, accuracy: 1e-9)
    }

    func testARowCutInTwoReadsIsStillRead() {
        let parser = CaptureLogParser()
        let full = row(0, bar: String(repeating: "-", count: 12)) + "\n"
        let cut = full.index(full.startIndex, offsetBy: 30)
        XCTAssertTrue(parser.feedOutput(String(full[..<cut])).isEmpty)
        XCTAssertEqual(parser.feedOutput(String(full[cut...])).count, 1)
    }

    func testTheAnnouncementOfTheDurationIsNotAWarning() {
        let parser = CaptureLogParser()
        XCTAssertTrue(parser.feedError(">>> to last 179.000000 seconds Press <Ctrl-C> to stop before that.\n").isEmpty)
        XCTAssertTrue(parser.feedError("to last 179.000000 seconds Press <Ctrl-C> to stop before that.\n").isEmpty)
    }

    func testTheIECScale() {
        XCTAssertEqual(IECScale.fraction(db: 0), 1)
        XCTAssertEqual(IECScale.fraction(db: -20), 0.5, accuracy: 1e-9)
        XCTAssertEqual(IECScale.fraction(db: -80), 0)
        XCTAssertLessThan(IECScale.fraction(db: -40), IECScale.fraction(db: -30))
    }

    func testTheDiskThreadIsNormalWithoutTheMark() {
        let normal = status.replacingOccurrences(of: "[x]", with: "[ ]")
        guard case .status(let s)? = CaptureLogParser().feedOutput(normal).first else { return XCTFail("no status") }
        XCTAssertFalse(s.diskThreadHighPriority)
    }

    func testTheMessagesOnTheErrorOutput() {
        let parser = CaptureLogParser()
        XCTAssertEqual(parser.feedError("\u{1B}[31m>>> Recording to \"Prise_01.wav\". Press <Return> or <Ctrl-C> to stop.\n\u{1B}[0m"),
                       [.recording(file: "Prise_01.wav")])
        XCTAssertEqual(parser.feedError("\u{1B}[31m>>> Waiting for JackTransportRolling.\n\u{1B}[0m"), [.waitingForJack("Waiting for JackTransportRolling.")])
        XCTAssertEqual(parser.feedError(">>> Waiting to start recording of \"Three_01.wav\"\n>>> Press <Ctrl-C> to stop recording and quit.\n"),
                       [.waitingToStart(file: "Three_01.wav")])
        XCTAssertEqual(parser.feedError("Could not connect input port Jack Capture:input1 to a:1, errorcode No such file\n"),
                       [.message("Could not connect input port Jack Capture:input1 to a:1, errorcode No such file")])
        XCTAssertEqual(parser.feedError("\u{1B}[31mFinished.\u{1B}[0m"), [.finished])
    }

    func testTheFlushAfterAStop() {
        XCTAssertEqual(CaptureLogParser().feedOutput(">>> Please wait while writing all data to disk. (shouldn't take long)\n"), [.flushing])
    }
}

/// The runner, against a script that behaves like jack_capture: it says what it does, draws its status line, and
/// finishes on SIGINT.
@MainActor
final class CaptureRunnerTests: XCTestCase {
    private func script(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jcr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fake_capture.sh")
        try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testItStartsReadsAndStopsWithSIGINT() async throws {
        let url = try script(#"""
        trap 'echo ">>> Please wait while writing all data to disk. (shouldnt take long)"; printf "\033[31mFinished.\033[0m\n" >&2; exit 0' INT
        printf '\033[31m>>> Recording to "Test_01.wav". Press <Return> or <Ctrl-C> to stop.\n\033[0m' >&2
        while true; do printf '\033[32mBuffer: 4.01s./4.01s    Time: 0.00m.   DHP: [ ]  Overruns: 0  Xruns: 1\033[0m\n'; sleep 0.1; done
        """#)
        let runner = CaptureRunner(executable: url, arguments: ["-c", "2"], directory: url.deletingLastPathComponent())
        var events: [CaptureEvent] = []
        var exit: (Int32, Bool)?
        let done = expectation(description: "exit")
        runner.onEvent = { events.append($0) }
        runner.onExit = { exit = ($0, $1); done.fulfill() }
        try runner.start()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(runner.isRunning)
        runner.stop()
        await fulfillment(of: [done], timeout: 10)
        XCTAssertEqual(exit?.0, 0)
        XCTAssertEqual(exit?.1, true)   // the stop was asked for
        XCTAssertTrue(events.contains(.recording(file: "Test_01.wav")))
        XCTAssertTrue(events.contains { if case .status(let s) = $0 { return s.xruns == 1 } else { return false } })
        XCTAssertTrue(events.contains(.flushing))
        XCTAssertTrue(events.contains(.finished))
    }

    func testAProgramThatEndsByItselfIsReportedAsNotStopped() async throws {
        let url = try script("echo 'Could not open' >&2\nexit 3\n")
        let runner = CaptureRunner(executable: url, arguments: [], directory: url.deletingLastPathComponent())
        var events: [CaptureEvent] = []
        var exit: (Int32, Bool)?
        let done = expectation(description: "exit")
        runner.onEvent = { events.append($0) }
        runner.onExit = { exit = ($0, $1); done.fulfill() }
        try runner.start()
        await fulfillment(of: [done], timeout: 10)
        XCTAssertEqual(exit?.0, 3)
        XCTAssertEqual(exit?.1, false)
        XCTAssertEqual(events, [.message("Could not open")])
    }

    func testReturnReachesTheProgram() async throws {
        let url = try script("read line\necho started >&2\nsleep 5\n")
        let runner = CaptureRunner(executable: url, arguments: [], directory: url.deletingLastPathComponent())
        var events: [CaptureEvent] = []
        runner.onEvent = { events.append($0) }
        try runner.start()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(events.isEmpty)
        runner.sendReturn()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(events, [.message("started")])
        runner.terminate()
    }

    func testAMissingProgramIsAnError() {
        let runner = CaptureRunner(executable: URL(fileURLWithPath: "/nonexistent/jack_capture"), arguments: [], directory: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try runner.start()) { XCTAssertEqual($0 as? CaptureRunner.LaunchError, .executableNotFound) }
    }
}
