// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import JackPlayKit

/// The levels and the position that the real jack_play reports, in both modes, on a JACK server of its own. Skipped when
/// the program or jackd is not there.
@MainActor
final class PlayerLevelsIntegrationTests: XCTestCase {
    private final class Box { var events = [PlayerEvent]() }

    private func program() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("build/jack_play")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("jack_play/build/jack_play is not built") }
        return url
    }

    private func server() throws -> (Process, String) {
        guard let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("jackd is not installed")
        }
        let name = "jptest\(UUID().uuidString.prefix(6))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: jackd)
        p.arguments = ["-n", name, "-d", "dummy", "-r", "48000", "-p", "1024"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        Thread.sleep(forTimeInterval: 2)
        return (p, name)
    }

    private func wait(_ what: String, timeout: Double = 8, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), what)
    }

    private func levels(_ events: [PlayerEvent]) -> [[Float]] { events.compactMap { if case .levels(let v) = $0 { return v }; return nil } }

    func testTheLevelsFollowThePlayerAndStopWhenItPauses() async throws {
        let program = try program()
        let (jackd, name) = try server()
        defer { jackd.terminate(); jackd.waitUntilExit() }
        let files = try TestFiles()
        let file = try files.write(TestFiles.all[0], channels: 2, frames: 48000 * 8)   // 0.5 and 0.25
        var env = ProcessInfo.processInfo.environment
        env["JACK_DEFAULT_SERVER"] = name
        let player = PlayerProcess(executable: program, command: PlayerCommand(file: file), environment: env)
        let box = Box()
        player.onEvent = { box.events.append($0) }
        try player.start()
        await wait("ready") { box.events.contains { if case .ready = $0 { return true }; return false } }

        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(levels(box.events).isEmpty, "paused at the start: no levels")

        player.send(.play)
        await wait("levels") { self.levels(box.events).count > 10 }
        try await Task.sleep(nanoseconds: 300_000_000)
        var highest: [Float] = [0, 0]
        for v in levels(box.events) { for i in 0..<2 { highest[i] = max(highest[i], v[i]) } }
        XCTAssertEqual(highest[0], 0.5, accuracy: 0.01)
        XCTAssertEqual(highest[1], 0.25, accuracy: 0.01, "the second channel is 6 dB under the first, as in the file")

        // A steady tone reads steady: the lines come about thirty times a second, none of them with the zeros of a window too short.
        let steady = levels(box.events).dropFirst(3)
        XCTAssertTrue(steady.allSatisfy { $0[0] > 0.45 && $0[1] > 0.2 }, "the levels do not flicker: \(steady.map { $0[0] })")

        // Through the meters of the display, as the application will show them.
        var tracker = LevelTracker()
        tracker.update(peaks: highest)
        XCTAssertEqual(tracker.meters[0].level, IECScale.fraction(db: -6.02), accuracy: 0.01)
        XCTAssertFalse(tracker.meters[0].clipped)

        // Levels off: one last line with the zeros, then nothing; on again: the levels come back.
        player.send(.levels(false))
        try await Task.sleep(nanoseconds: 300_000_000)
        let silent = box.events.count
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(levels(box.events).last, [0, 0], "the last line says the zeros")
        XCTAssertEqual(box.events.filter { if case .levels = $0 { return true }; return false }.count,
                       levels(Array(box.events.prefix(silent))).count, "no more levels while they are off")
        player.send(.levels(true))
        await wait("levels again") { self.levels(box.events).last?[0] ?? 0 > 0.4 }

        player.send(.pause)
        try await Task.sleep(nanoseconds: 500_000_000)   // the fade out, and the line with the zeros
        let afterPause = box.events.count
        XCTAssertEqual(levels(box.events).last, [0, 0], "one last line with the zeros")
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(box.events.count, afterPause, "a paused player says nothing")

        player.stop()
        await wait("exit") { box.events.contains { if case .exited = $0 { return true }; return false } }
    }

    func testFollowingTheTransportReportsToo() async throws {
        let program = try program()
        let (jackd, name) = try server()
        defer { jackd.terminate(); jackd.waitUntilExit() }
        setenv("JACK_DEFAULT_SERVER", name, 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }
        let bridge = JackBridgeWrapper()
        try bridge.open(clientName: "transport")
        defer { bridge.close() }
        let files = try TestFiles()
        let file = try files.write(TestFiles.all[1], channels: 2, frames: 44100 * 8)   // 44.1 kHz on a 48 kHz server
        var env = ProcessInfo.processInfo.environment
        env["JACK_DEFAULT_SERVER"] = name
        let command = PlayerCommand(file: file, mode: .followTransport)
        let player = PlayerProcess(executable: program, command: command, environment: env)
        let box = Box()
        player.onEvent = { box.events.append($0) }
        try player.start()
        await wait("ready") { box.events.contains { if case .ready(2, 44100, 48000, _) = $0 { return true }; return false } }

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(levels(box.events).isEmpty, "the transport is stopped: nothing plays")

        bridge.transportStart()
        await wait("levels while the transport rolls") { self.levels(box.events).count > 10 }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(box.events.contains { if case .position(_, .playing) = $0 { return true }; return false })

        bridge.transportStop()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(box.events.contains(.position(frame: box.events.compactMap { if case .position(let f, .paused) = $0 { return f }; return nil }.last ?? -1, state: .paused)))
        XCTAssertEqual(levels(box.events).last, [0, 0])

        // A locate to 2.000 s of the transport lands at 2.000 s of the file, at 44.1 kHz: 88200 frames of the file.
        bridge.transportLocate(frame: 96000)
        try await Task.sleep(nanoseconds: 500_000_000)
        let reported = box.events.compactMap { e -> Int64? in if case .position(let f, _) = e { return f }; return nil }.last
        XCTAssertEqual(try XCTUnwrap(reported), 88200, accuracy: 600, "the position is in frames of the file, not of the server")

        player.terminate()
        await wait("exit") { box.events.contains { if case .exited = $0 { return true }; return false } }
    }
}
