// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

/// The real jack_play (the universal binary of jack_play/build), on a JACK server of its own, so that the one of the
/// person is not touched. Skipped when the program or jackd is not there.
@MainActor
final class PlayerIntegrationTests: XCTestCase {
    private func jackPlay() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("build/jack_play")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("jack_play/build/jack_play is not built") }
        return url
    }

    private func startServer(name: String) throws -> Process {
        let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let jackd else { throw XCTSkip("jackd is not installed") }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", name, "-d", "dummy", "-r", "48000", "-p", "1024"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        Thread.sleep(forTimeInterval: 2)
        return server
    }

    final class Box { var events = [PlayerEvent]() }

    private func wait(_ box: Box, timeout: TimeInterval = 8, _ what: String, for condition: @escaping ([PlayerEvent]) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(box.events), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(box.events), "\(what): \(box.events.suffix(6))")
    }

    func testTheRealProgramPlaysPausesAndSeeks() async throws {
        let program = try jackPlay()
        let serverName = "jptest\(UUID().uuidString.prefix(6))"
        let server = try startServer(name: serverName)
        defer { server.terminate(); server.waitUntilExit() }
        let files = try TestFiles()
        let file = try files.write(TestFiles.all[1], channels: 2, frames: 44100 * 4)   // 44.1 kHz on a 48 kHz server
        var environment = ProcessInfo.processInfo.environment
        environment["JACK_DEFAULT_SERVER"] = serverName
        let process = PlayerProcess(executable: program, command: PlayerCommand(file: file), environment: environment)
        let box = Box()
        process.onEvent = { box.events.append($0) }
        try process.start()

        await wait(box, "ready") { $0.contains { if case .ready(let c, let fr, let sr, let n) = $0 { return c == 2 && fr == 44100 && sr == 48000 && n == 176_400 }; return false } }
        // It starts paused, at the beginning.
        await wait(box, "paused at 0") { $0.contains(.position(frame: 0, state: .paused)) }

        process.send(.play)
        await wait(box, "playing") { $0.contains { if case .position(let f, .playing) = $0 { return f > 4000 }; return false } }

        process.send(.seek(88200))   // 2.000 s of the file, in frames of the file
        await wait(box, "seek") { $0.contains { if case .position(let f, _) = $0 { return f >= 88200 && f < 88200 + 44100 / 2 }; return false } }

        process.send(.pause)
        try await Task.sleep(nanoseconds: 400_000_000)
        let resting = box.events.reversed().compactMap { e -> Int64? in if case .position(let f, .paused) = e { return f }; return nil }.first
        try await Task.sleep(nanoseconds: 600_000_000)
        let later = box.events.reversed().compactMap { e -> Int64? in if case .position(let f, .paused) = e { return f }; return nil }.first
        XCTAssertNotNil(resting)
        XCTAssertEqual(resting, later, "the position moved while paused")

        process.send(.seek(0))
        process.send(.play)
        // At the end, the state says so.
        process.send(.seek(176_400 - 44100 / 4))
        await wait(box, timeout: 8, "ended") { $0.contains(.position(frame: 176_400, state: .ended)) }

        process.stop()
        await wait(box, "exit") { $0.contains { if case .exited = $0 { return true }; return false } }
        XCTAssertEqual(box.events.last, .exited(status: 0, requested: true))
    }
}
