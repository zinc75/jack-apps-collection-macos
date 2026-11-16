// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import JackPlayKit

/// The whole model with the real program, the real graph and a client that measures: opening a file, the connections of
/// the matrix, playing, seeking, pausing, and the program started again when an option changes. Skipped when the program or
/// jackd is not there.
@MainActor
final class PlayerModelIntegrationTests: XCTestCase {
    private func wait(_ what: String, timeout: Double = 10, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), what)
    }

    func testTheModelPlaysAFileThroughTheRealPlayer() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let program = repo.appendingPathComponent("build/jack_play")
        guard FileManager.default.isExecutableFile(atPath: program.path) else { throw XCTSkip("jack_play/build/jack_play is not built") }
        guard let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("jackd is not installed")
        }
        let serverName = "jptest\(UUID().uuidString.prefix(6))"
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
        let meter = JackBridgeWrapper()
        try meter.open(clientName: "dest")
        XCTAssertEqual(meter.registerMeterPorts(count: 2), 2)
        defer { meter.close() }
        graph.refresh()

        let suite = "jackplay-int-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var env = ProcessInfo.processInfo.environment
        env["JACK_DEFAULT_SERVER"] = serverName
        let model = PlayerModel(server: graph, store: ConnectionStore(defaults: defaults)) { command in
            PlayerProcess(executable: program, command: command, environment: env)
        }
        defer { model.closeFile() }
        let files = try TestFiles()
        let url = try files.write(TestFiles.all[0], channels: 2, frames: 48000 * 12)   // 0.5 and 0.25

        model.open(url)
        await wait("the player is ready") { model.phase == .running(.paused) }
        XCTAssertEqual(model.duration, 12, accuracy: 1e-9)
        // The first time, the channels go to the first outputs of the system.
        XCTAssertEqual(model.routing.channels, [["system:playback_1"], ["system:playback_2"]])
        var client = try XCTUnwrap(graph.bridge.getPorts().map(\.id).first { $0.hasPrefix("jack_play") && $0.hasSuffix(":out_1") }).replacingOccurrences(of: ":out_1", with: "")
        XCTAssertEqual(graph.destinations(of: "\(client):out_1"), ["system:playback_1"])

        // The matrix sends the channels to the client that measures.
        model.setRouting(ChannelRouting(channels: [["dest:in1"], ["dest:in2"]]))
        XCTAssertEqual(graph.destinations(of: "\(client):out_1"), ["dest:in1"])
        XCTAssertTrue(graph.destinations(of: "\(client):out_1").isDisjoint(with: ["system:playback_1"]))

        _ = meter.takeMeterPeak(channel: 0); _ = meter.takeMeterPeak(channel: 1)
        model.play()
        await wait("it plays") { model.isPlaying && model.position > 4800 }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(try XCTUnwrap(meter.takeMeterPeak(channel: 0)), 0.5, accuracy: 0.06)
        XCTAssertEqual(try XCTUnwrap(meter.takeMeterPeak(channel: 1)), 0.25, accuracy: 0.06)
        XCTAssertEqual(model.meters.count, 2)
        XCTAssertGreaterThan(model.meters[0].level, model.meters[1].level, "the first channel is louder, as in the file")

        // A click on the waveform: 6.000 s.
        model.seek(fraction: 0.5)
        await wait("it is at the new place") { model.position > 280_000 && model.position < 330_000 }
        XCTAssertTrue(model.isPlaying)

        model.pause()
        await wait("it pauses") { model.phase == .running(.paused) }
        let resting = model.position
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(model.position, resting, "the position does not move while paused")
        await wait("the meters fall") { model.meters.allSatisfy { $0.level < 0.01 } }

        // An option changes: the program starts again where it was, and the connections are made again.
        model.update(settings: PlayerSettings(loop: true))
        await wait("the program is back") { model.phase == .running(.paused) && model.position >= resting - 4800 }
        client = try XCTUnwrap(graph.bridge.getPorts().map(\.id).first { $0.hasPrefix("jack_play") && $0.hasSuffix(":out_1") }).replacingOccurrences(of: ":out_1", with: "")
        XCTAssertEqual(graph.destinations(of: "\(client):out_1"), ["dest:in1"], "the connections follow the new program")
        XCTAssertTrue(model.commandLine?.contains(" -l ") == true)
        XCTAssertEqual(Double(model.position), Double(resting), accuracy: 4800)
    }
}
