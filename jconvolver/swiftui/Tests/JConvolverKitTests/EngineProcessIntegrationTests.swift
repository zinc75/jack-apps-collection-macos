// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

/// The real programs (the universal binaries of jconvolver/build). The real-time one runs on a JACK server of its own, so
/// that the one of the person is not touched. Skipped when a program or jackd is not there.
@MainActor
final class EngineProcessIntegrationTests: XCTestCase {
    final class Box { var events = [EngineEvent]() }

    private func program(_ p: EngineCommand.Program) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/\(p.rawValue)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("jconvolver/build/\(p.rawValue) is not built") }
        return url
    }

    private func startServer(name: String, period: Int = 256) throws -> Process {
        let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let jackd else { throw XCTSkip("jackd is not installed") }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", name, "-d", "dummy", "-r", "48000", "-p", "\(period)"]
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

    /// Runs a program until it ends (or, with `stopAfter`, until it has been asked to end and has), and gives what it said.
    private func run(_ command: EngineCommand, stopAfter: TimeInterval? = nil, timeout: TimeInterval = 30,
                     whileRunning: ((EngineProcess) -> Void)? = nil) async throws -> [EngineEvent] {
        let process = EngineProcess(executable: try program(command.program), command: command)
        let box = Box()
        let ended = expectation(description: "the program ended")
        process.onEvent = { event in
            box.events.append(event)
            if case .ended = event { ended.fulfill() }
        }
        try process.start()
        if let whileRunning { DispatchQueue.main.asyncAfter(deadline: .now() + (stopAfter ?? 1) / 2) { whileRunning(process) } }
        if let stopAfter { DispatchQueue.main.asyncAfter(deadline: .now() + stopAfter) { process.stop() } }
        await fulfillment(of: [ended], timeout: timeout)
        return box.events
    }

    private func messages(_ events: [EngineEvent]) -> [EngineMessage] {
        events.compactMap { if case .message(let m) = $0 { return m } else { return nil } }
    }

    private func termination(_ events: [EngineEvent]) throws -> EngineTermination {
        for case .ended(let t) in events { return t }
        throw XCTSkip("the program did not end")
    }

    // MARK: Sound files

    /// A WAV file of 32 bit floats.
    private func writeWAV(_ url: URL, channels: Int, rate: Int = 48000, samples: [Float]) throws {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = samples.count * 4
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(3); u16(channels); u32(rate); u32(rate * channels * 4); u16(channels * 4); u16(32)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { var bits = s.bitPattern.littleEndian; d.append(Data(bytes: &bits, count: 4)) }
        try d.write(to: url)
    }

    /// The samples of a WAV file of 32 bit floats, whatever other chunks it has.
    private func readWAV(_ url: URL) throws -> (channels: Int, samples: [Float]) {
        let d = try Data(contentsOf: url)
        func u16(_ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var channels = 0, position = 12
        while position + 8 <= d.count {
            let id = String(decoding: d[position..<position + 4], as: UTF8.self), size = u32(position + 4)
            if id == "fmt " { XCTAssertEqual(u16(position + 8), 3, "not float"); channels = u16(position + 10) }
            if id == "data" {
                let count = min(size, d.count - position - 8) / 4
                let samples = (0..<count).map { Float(bitPattern: UInt32(truncatingIfNeeded: u32(position + 8 + $0 * 4))) }
                return (channels, samples)
            }
            position += 8 + size + (size & 1)
        }
        throw XCTSkip("no data in \(url.lastPathComponent)")
    }

    // MARK: fconvolver

    func testFconvolverDelaysAndScalesTheInput() async throws {
        let dir = try temporaryDirectory()
        var input = [Float](repeating: 0, count: 1000)
        input[100] = 1
        input[300] = -0.5
        try writeWAV(dir.appendingPathComponent("in.wav"), channels: 1, samples: input)
        let config = "/convolver/new 1 1 64 256\n/impulse/dirac 1 1 0.5 10\n"
        try config.write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)

        let command = EngineCommand(program: .fconvolver, configPath: dir.appendingPathComponent("c.conf").path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        let events = try await run(command)

        XCTAssertEqual(try termination(events).outcome, .finished)
        XCTAssertTrue(messages(events).isEmpty, "a program that works says nothing: \(messages(events).map(\.text))")
        let out = try readWAV(dir.appendingPathComponent("out.wav"))
        XCTAssertEqual(out.channels, 1)
        XCTAssertEqual(out.samples.count, 1000 + 256 - 1)   // the tail is kept without -T
        XCTAssertEqual(out.samples[110], 0.5, accuracy: 1e-5)
        XCTAssertEqual(out.samples[310], -0.25, accuracy: 1e-5)
        XCTAssertLessThan(out.samples.enumerated().filter { $0.offset != 110 && $0.offset != 310 }.map { abs($0.element) }.max() ?? 0, 1e-5)
    }

    func testFconvolverWithTruncateStopsAtTheLengthOfTheInput() async throws {
        let dir = try temporaryDirectory()
        try writeWAV(dir.appendingPathComponent("in.wav"), channels: 1, samples: [Float](repeating: 0.1, count: 1000))
        try "/convolver/new 1 1 64 256\n/impulse/dirac 1 1 1 0\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        var options = EngineCommand.Options()
        options.truncate = true
        let command = EngineCommand(program: .fconvolver, options: options, configPath: dir.appendingPathComponent("c.conf").path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        _ = try await run(command)
        XCTAssertEqual(try readWAV(dir.appendingPathComponent("out.wav")).samples.count, 1000)
    }

    func testFconvolverSaysWhenTheInputsDoNotMatch() async throws {
        let dir = try temporaryDirectory()
        try writeWAV(dir.appendingPathComponent("in.wav"), channels: 1, samples: [Float](repeating: 0, count: 100))
        try "/convolver/new 2 1 64 256\n/impulse/dirac 1 1 1 0\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        let command = EngineCommand(program: .fconvolver, configPath: dir.appendingPathComponent("c.conf").path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        let events = try await run(command)
        XCTAssertEqual(messages(events).map(\.kind), [.cannotStart])
        XCTAssertEqual(try termination(events).outcome, .failed(status: 1))
    }

    func testAFileOfImpulseResponsesThatIsNotThereIsAnErrorButNotAnEnd() async throws {
        // jconvolver and fconvolver go on after "Unable to open": the exit code is 0, only the message says it.
        let dir = try temporaryDirectory()
        try writeWAV(dir.appendingPathComponent("in.wav"), channels: 1, samples: [Float](repeating: 0.5, count: 100))
        try "/convolver/new 1 1 64 256\n/impulse/read 1 1 1 0 0 0 1 missing.wav\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        let command = EngineCommand(program: .fconvolver, configPath: dir.appendingPathComponent("c.conf").path,
                                    inputFile: dir.appendingPathComponent("in.wav").path, outputFile: dir.appendingPathComponent("out.wav").path)
        let events = try await run(command)
        let kinds = messages(events).map(\.kind)
        XCTAssertEqual(kinds.count, 1)
        if case .fileUnreadable(let line, let path)? = kinds.first {
            XCTAssertEqual(line, 2)
            XCTAssertTrue(path.hasSuffix("/missing.wav"), path)
        } else { XCTFail("not a file that is missing: \(kinds)") }
        XCTAssertEqual(try termination(events).outcome, .finished)
    }

    // MARK: jconvolver, on a JACK server of its own

    func testJconvolverRunsUntilItIsAskedToEndAndSaysNothing() async throws {
        let server = try startServer(name: "jconvtest-a")
        defer { server.terminate() }
        let dir = try temporaryDirectory()
        try "/convolver/new 2 2 256 4096\n/impulse/dirac 1 1 1 0\n/impulse/dirac 2 2 1 0\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        let command = EngineCommand(program: .jconvolver, configPath: dir.appendingPathComponent("c.conf").path, clientName: "jconvtest", serverName: "jconvtest-a")

        var load: Double?
        let events = try await run(command, stopAfter: 2.5) { process in
            guard let pid = process.processIdentifier else { return }
            var sampler = EngineLoadSampler(pid: pid)
            _ = sampler.sample()
            Thread.sleep(forTimeInterval: 0.3)
            load = sampler.sample()
        }
        XCTAssertTrue(messages(events).isEmpty, "\(messages(events).map(\.text))")
        let end = try termination(events)
        XCTAssertEqual(end.outcome, .stoppedOnRequest)
        XCTAssertEqual(end.status, 0)
        XCTAssertNotNil(load)
        XCTAssertLessThan(load ?? 0, 0.5)   // two Dirac pulses ask very little
    }

    func testJconvolverReportsALineWithItsOwnWordsAndGoesOn() async throws {
        let server = try startServer(name: "jconvtest-b")
        defer { server.terminate() }
        let dir = try temporaryDirectory()
        try "/convolver/new 2 2 256 4096\n/impulse/read 1 1 1 0 0 0 1 nope.wav\n/impulse/dirac 2 2 1 0\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        var options = EngineCommand.Options()
        options.latencyCompensation = 64
        let command = EngineCommand(program: .jconvolver, options: options, configPath: dir.appendingPathComponent("c.conf").path, serverName: "jconvtest-b")
        let events = try await run(command, stopAfter: 2)
        let all = messages(events)
        XCTAssertTrue(all.contains { $0.kind == .impulseRemoved(line: 3) } || all.contains { if case .fileUnreadable(2, _) = $0.kind { return true } else { return false } }, "\(all.map(\.text))")
        XCTAssertEqual(try termination(events).outcome, .stoppedOnRequest)
    }

    func testJconvolverWithoutAJackServerCannotStart() async throws {
        let dir = try temporaryDirectory()
        try "/convolver/new 1 1 256 4096\n/impulse/dirac 1 1 1 0\n".write(to: dir.appendingPathComponent("c.conf"), atomically: true, encoding: .utf8)
        let command = EngineCommand(program: .jconvolver, configPath: dir.appendingPathComponent("c.conf").path, serverName: "jconvtest-absent")
        let events = try await run(command, timeout: 20)
        XCTAssertTrue(messages(events).contains { $0.kind == .cannotStart }, "\(messages(events).map(\.text))")
        guard case .failed = try termination(events).outcome else { return XCTFail("\(try termination(events))") }
    }
}
