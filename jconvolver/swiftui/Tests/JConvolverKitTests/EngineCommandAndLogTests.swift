// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class EngineCommandAndLogTests: XCTestCase {
    // MARK: Command lines

    func testJconvolverWithoutOptions() {
        let c = EngineCommand(program: .jconvolver, configPath: "/Users/eric/room.conf")
        XCTAssertEqual(c.arguments, ["/Users/eric/room.conf"])
        XCTAssertEqual(c.displayString, "jconvolver /Users/eric/room.conf")
    }

    func testJconvolverWithEveryOption() {
        var o = EngineCommand.Options()
        o.vectorMode = true; o.measure = true; o.denormalProtection = true; o.latencyCompensation = 600
        let c = EngineCommand(program: .jconvolver, options: o, configPath: "/a/room.conf", clientName: "Room", serverName: "default")
        XCTAssertEqual(c.arguments, ["-V", "-M", "-Z", "-L", "600", "-N", "Room", "-s", "default", "/a/room.conf"])
    }

    func testZeroLatencyCompensationIsNotPassed() {
        XCTAssertEqual(EngineCommand(program: .jconvolver, configPath: "c.conf").arguments, ["c.conf"])
    }

    func testFconvolver() {
        var o = EngineCommand.Options()
        o.vectorMode = true; o.measure = true; o.truncate = true
        o.denormalProtection = true; o.latencyCompensation = 100   // not options of this program
        let c = EngineCommand(program: .fconvolver, options: o, configPath: "c.conf", clientName: "x", serverName: "y",
                              inputFile: "in.wav", outputFile: "out.wav")
        XCTAssertEqual(c.arguments, ["-V", "-M", "-T", "c.conf", "in.wav", "out.wav"])
    }

    func testTheCommandLineCanBePastedInATerminal() {
        let c = EngineCommand(program: .jconvolver, configPath: "/Users/eric/My Rooms/it's.conf")
        XCTAssertEqual(c.displayString, "jconvolver '/Users/eric/My Rooms/it'\\''s.conf'")
    }

    // MARK: The journal

    func testEntriesKeepTheirOrderAndNumbers() {
        var log = EngineLog()
        log.append(source: .app, "Lancement", startsRun: true)
        log.append(EngineMessage.classify("Computation threads are late (0001)."))
        log.append(EngineMessage.classify("CPU overload, exiting."))
        XCTAssertEqual(log.entries.map(\.id), [0, 1, 2])
        XCTAssertEqual(log.entries.map(\.source), [.app, .engine, .engine])
        XCTAssertEqual(log.entries.map(\.severity), [.info, .warning, .error])
        XCTAssertEqual(log.warningCount, 1)
        XCTAssertEqual(log.errorCount, 1)
    }

    func testOnlyProblemsKeepsTheOpeningOfARun() {
        var log = EngineLog()
        log.append(source: .app, "Lancement", startsRun: true)
        log.append(source: .jack, "client connecté")
        log.append(source: .jack, severity: .warning, "xrun")
        XCTAssertEqual(log.entries(onlyProblems: true).map(\.text), ["Lancement", "xrun"])
        XCTAssertEqual(log.entries(onlyProblems: false).count, 3)
    }

    func testTheOldestLinesGoFirst() {
        var log = EngineLog()
        log.capacity = 3
        for i in 0..<5 { log.append(source: .app, "ligne \(i)") }
        XCTAssertEqual(log.entries.map(\.text), ["ligne 2", "ligne 3", "ligne 4"])
        XCTAssertEqual(log.entries.map(\.id), [2, 3, 4])
    }

    func testPlainTextOfTheJournal() {
        var log = EngineLog()
        log.append(source: .engine, severity: .warning, "Line 1: Data truncated.")
        XCTAssertTrue(log.plainText().hasSuffix("  engine  Line 1: Data truncated."))
        log.clear()
        XCTAssertEqual(log.plainText(), "")
    }

    // MARK: Load

    func testCoresAndShareOfTheMachine() {
        XCTAssertEqual(EngineLoad.cores(cpuSeconds: 0.5, wallSeconds: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EngineLoad.cores(cpuSeconds: 3, wallSeconds: 1), 3, accuracy: 1e-9)   // three threads busy
        XCTAssertEqual(EngineLoad.cores(cpuSeconds: 1, wallSeconds: 0), 0)
        XCTAssertEqual(EngineLoad.machineShare(cores: 0.72, coreCount: 18), 0.04, accuracy: 1e-9)
    }

    func testTheLoadOfARealProcess() throws {
        // A process that does nothing but compute takes about one core.
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try busy.run()
        defer { busy.terminate() }
        var sampler = EngineLoadSampler(pid: busy.processIdentifier)
        XCTAssertNil(sampler.sample())   // the first reading has no period
        Thread.sleep(forTimeInterval: 1.0)
        let cores = try XCTUnwrap(sampler.sample())
        XCTAssertGreaterThan(cores, 0.5)
        XCTAssertLessThan(cores, 1.5)
    }

    func testAProcessThatIsGoneCannotBeRead() {
        XCTAssertNil(EngineLoadSampler.cpuSeconds(of: 999_999))
    }
}
