// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

/// The controller on the real programs (jconvolver/build), the real-time one on a JACK server of its own. Skipped when a
/// program or jackd is not there.
@MainActor
final class EngineControllerTests: XCTestCase {
    private func program(_ p: EngineCommand.Program) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/\(p.rawValue)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("jconvolver/build/\(p.rawValue) is not built") }
        return url
    }

    private func startServer(name: String) throws -> Process {
        let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let jackd else { throw XCTSkip("jackd is not installed") }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", name, "-d", "dummy", "-r", "48000", "-p", "256"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        Thread.sleep(forTimeInterval: 2)
        return server
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jconvolver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Waits for something that happens on the main queue.
    private func wait(timeout: TimeInterval = 20, until condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func writeConfig(_ text: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("c.conf")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A 16 bit mono WAV of silence, which fconvolver can read.
    private func writeSilence(_ url: URL, frames: Int) throws {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + frames * 2); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(48000); u32(96000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(frames * 2)
        d.append(Data(count: frames * 2))
        try d.write(to: url)
    }

    // MARK: A program that does its work

    func testARunOfFconvolverIsWrittenInTheJournalAndEndsFinished() async throws {
        let dir = try temporaryDirectory()
        try writeSilence(dir.appendingPathComponent("in.wav"), frames: 4800)
        let config = try writeConfig("/convolver/new 1 1 64 256\n/impulse/dirac 1 1 1 0\n", in: dir)
        let command = EngineCommand(program: .fconvolver, configPath: config.path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        let controller = EngineController()
        XCTAssertEqual(controller.state, .idle)
        try controller.start(command, executable: try program(.fconvolver))

        let ended = await wait { if case .ended = controller.state { return true } else { return false } }
        XCTAssertTrue(ended)
        XCTAssertEqual(controller.state, .ended(EngineTermination(status: 0, outcome: .finished)))
        XCTAssertFalse(controller.endedOnAProblem)
        XCTAssertFalse(controller.isRunning)

        let notes = controller.log.entries.compactMap(\.note)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first, .launch(commandLine: command.displayString))
        XCTAssertEqual(notes.last, .ended(program: "fconvolver", status: 0))
        XCTAssertTrue(controller.log.entries.first?.startsRun == true)
        XCTAssertNil(controller.cores)
    }

    func testAnErrorOfTheProgramIsInTheJournalAndTheRunEndsOnAProblem() async throws {
        let dir = try temporaryDirectory()
        try writeSilence(dir.appendingPathComponent("in.wav"), frames: 100)
        let config = try writeConfig("/convolver/new 2 1 64 256\n/impulse/dirac 1 1 1 0\n", in: dir)   // two inputs, a mono file
        let command = EngineCommand(program: .fconvolver, configPath: config.path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        let controller = EngineController()
        try controller.start(command, executable: try program(.fconvolver))
        _ = await wait { if case .ended = controller.state { return true } else { return false } }

        XCTAssertTrue(controller.endedOnAProblem)
        XCTAssertEqual(controller.state, .ended(EngineTermination(status: 1, outcome: .failed(status: 1))))
        XCTAssertEqual(controller.log.errorCount, 2)   // what the program said, and its end with an error
        XCTAssertTrue(controller.log.entries.contains { $0.source == .engine && $0.text.contains("doesn't match") })
    }

    func testAProgramThatIsNotThereCannotStart() throws {
        let controller = EngineController()
        let command = EngineCommand(program: .jconvolver, configPath: "/nope.conf")
        XCTAssertThrowsError(try controller.start(command, executable: URL(fileURLWithPath: "/nope/jconvolver"))) {
            XCTAssertEqual($0 as? EngineProcess.LaunchError, .executableNotFound)
        }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.log.entries.compactMap(\.note), [.launch(commandLine: command.displayString), .cannotLaunch(reason: "program not found")])
        XCTAssertEqual(controller.log.errorCount, 1)
    }

    // MARK: The real-time program

    func testAnEngineRunsIsMeasuredCountsTheCutsAndIsStopped() async throws {
        let server = try startServer(name: "jconvtest-c")
        defer { server.terminate() }
        let dir = try temporaryDirectory()
        let config = try writeConfig("/convolver/new 2 2 256 4096\n/impulse/dirac 1 1 1 0\n/impulse/dirac 2 2 1 0\n", in: dir)
        let command = EngineCommand(program: .jconvolver, configPath: config.path, clientName: "jconvtest", serverName: "jconvtest-c")
        let controller = EngineController()
        controller.sampleInterval = 0.2

        try controller.start(command, executable: try program(.jconvolver))
        XCTAssertEqual(controller.state, .running)
        XCTAssertTrue(controller.isRunning)

        // A second start while it runs does nothing.
        try controller.start(command, executable: try program(.jconvolver))
        XCTAssertEqual(controller.log.entries.filter(\.startsRun).count, 1)

        let measured = await wait { controller.cores != nil }
        XCTAssertTrue(measured)
        XCTAssertLessThan(controller.cores ?? 9, 0.5)
        XCTAssertEqual(controller.machineShare ?? 9, (controller.cores ?? 0) / Double(ProcessInfo.processInfo.activeProcessorCount), accuracy: 1e-9)

        controller.recordXrun(microseconds: 1380)
        controller.recordXrun(microseconds: 410)
        XCTAssertEqual(controller.xruns, 2)
        XCTAssertEqual(controller.log.entries.filter { $0.source == .jack }.map(\.severity), [.warning, .warning])

        controller.stop()
        XCTAssertEqual(controller.state, .stopping)
        let ended = await wait { if case .ended = controller.state { return true } else { return false } }
        XCTAssertTrue(ended)
        XCTAssertEqual(controller.state, .ended(EngineTermination(status: 0, outcome: .stoppedOnRequest)))
        XCTAssertFalse(controller.endedOnAProblem)
        XCTAssertNil(controller.cores)
        XCTAssertEqual(controller.log.entries.compactMap(\.note).filter { if case .stopRequested = $0 { return true } else { return false } }.count, 1)
        XCTAssertEqual(controller.log.entries.compactMap(\.note).last, .ended(program: "jconvolver", status: 0))

        // The cuts that come after the end are not counted.
        controller.recordXrun(microseconds: 1)
        XCTAssertEqual(controller.xruns, 2)

        controller.acknowledgeEnd()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.log.entries.isEmpty)   // the journal stays
    }

    func testANewRunStartsANewSectionOfTheJournal() async throws {
        let server = try startServer(name: "jconvtest-d")
        defer { server.terminate() }
        let dir = try temporaryDirectory()
        let config = try writeConfig("/convolver/new 1 1 256 4096\n/impulse/dirac 1 1 1 0\n", in: dir)
        let command = EngineCommand(program: .jconvolver, configPath: config.path, serverName: "jconvtest-d")
        let controller = EngineController()
        for _ in 0..<2 {
            try controller.start(command, executable: try program(.jconvolver))
            try await Task.sleep(for: .milliseconds(800))
            controller.stop()
            let ended = await wait { if case .ended = controller.state { return true } else { return false } }
            XCTAssertTrue(ended)
        }
        XCTAssertEqual(controller.log.entries.filter(\.startsRun).count, 2)
        controller.clearLog()
        XCTAssertTrue(controller.log.entries.isEmpty)
    }
}
