// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import JackPlayKit

/// Two files that follow each other with the real program, the real graph and a server of its own: the file that comes next is
/// started in advance, told when the first one ends, and becomes the player. The files differ in rate and in channels. Skipped
/// when the program or jackd is not there.
@MainActor
final class PlayerChainIntegrationTests: XCTestCase {
    private func wait(_ what: String, timeout: Double = 15, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), what)
    }

    func testTwoFilesOfDifferentRatesAndChannelsFollowEachOther() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let program = repo.appendingPathComponent("build/jack_play")
        guard FileManager.default.isExecutableFile(atPath: program.path) else { throw XCTSkip("jack_play/build/jack_play is not built") }
        guard let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("jackd is not installed")
        }
        let serverName = "jpc\(UUID().uuidString.prefix(4))"
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", serverName, "-d", "dummy", "-r", "48000", "-p", "1024"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        setenv("JACK_DEFAULT_SERVER", serverName, 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }

        let graph = PlaybackGraph()
        graph.start()
        defer { graph.stop() }
        await wait("the graph connects") { graph.isConnected }

        let suite = "jackplay-chain-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var env = ProcessInfo.processInfo.environment
        env["JACK_DEFAULT_SERVER"] = serverName
        let model = PlayerModel(server: graph, store: ConnectionStore(defaults: defaults)) { command in
            PlayerProcess(executable: program, command: command, environment: env)
        }
        defer { model.closeFile() }
        let files = try TestFiles()
        let a = try files.write(TestFiles.all[1], channels: 2, frames: 44100 * 2)    // 44.1 kHz, 2 s, stereo
        let b = try files.write(TestFiles.all[2], channels: 1, frames: 96000 * 2)    // 96 kHz, 2 s, mono

        var ended = 0
        // What the playlist does: go on to the next file, and say which one comes after it (none here).
        model.onFileEnded = { ended += 1; if model.advanceToNext(play: true) { model.nextFile = nil } }
        model.listCount = 2; model.currentNumber = 1; model.nextNumber = 2
        model.open(a)
        await wait("the first file is ready") { model.phase == .running(.paused) }
        model.nextFile = b
        await wait("the next file is ready, in advance") { model.nextIsReady }
        // Two programs live together, with two names, until the first one ends.
        let clients = Set(graph.bridge.getPorts().map(\.clientName))
        XCTAssertTrue(clients.contains("01 of 02 - jack_play"), "\(clients)")
        XCTAssertTrue(clients.contains("02 of 02 - jack_play"), "\(clients)")

        model.play()
        await wait("the first file plays") { model.isPlaying && model.position > 4800 }
        await wait("the second file takes over", timeout: 8) { model.file?.url == b }
        XCTAssertEqual(model.file?.info.channels, 1)
        XCTAssertEqual(ended, 1)
        await wait("and plays") { model.isPlaying && model.position > 4800 }
        // The first program has left the graph.
        await wait("the first program is gone") { !Set(graph.bridge.getPorts().map(\.clientName)).contains("jack_play") }
        // Nothing comes after the second file: it ends and stops there.
        await wait("the second file ends", timeout: 8) { model.hasEnded }
        XCTAssertEqual(ended, 2)
        XCTAssertEqual(model.file?.url, b)
    }
}
