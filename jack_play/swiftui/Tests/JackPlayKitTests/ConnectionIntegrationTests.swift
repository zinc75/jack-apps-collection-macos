// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import JackPlayKit

/// The real jack_play, the real graph and the real connection manager, on a JACK server of its own: the player is
/// connected to a client that measures what it receives. Skipped when the program or jackd is not there.
@MainActor
final class ConnectionIntegrationTests: XCTestCase {
    private func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    private func waitFor(_ what: String, timeout: Double = 8, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { await sleep(0.02) }
        XCTAssertTrue(condition(), what)
    }

    func testTheRoutingReachesTheRealPorts() async throws {
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
        await sleep(2)
        setenv("JACK_DEFAULT_SERVER", serverName, 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }

        let graph = PlaybackGraph()
        graph.start()
        defer { graph.stop() }
        await waitFor("the graph connects to the server") { graph.isConnected }

        // A client with two inputs that measure what they receive.
        let meter = JackBridgeWrapper()
        try meter.open(clientName: "dest")
        XCTAssertEqual(meter.registerMeterPorts(count: 2), 2)
        graph.refresh()
        XCTAssertEqual(graph.destinations.first?.name, "system", "the sound card comes first")
        XCTAssertEqual(graph.destinations.first(where: { $0.name == "dest" })?.ports, ["in1", "in2"])
        XCTAssertFalse(graph.playbackPorts.isEmpty)

        // The player, on a stereo file: 0.5 on the first channel, 0.25 on the second.
        let files = try TestFiles()
        let file = try files.write(TestFiles.all[0], channels: 2, frames: 48000 * 6)
        var environment = ProcessInfo.processInfo.environment
        environment["JACK_DEFAULT_SERVER"] = serverName
        let player = PlayerProcess(executable: program, command: PlayerCommand(file: file), environment: environment)
        var ready = false
        player.onEvent = { if case .ready = $0 { ready = true } }
        try player.start()
        await waitFor("the player is ready") { ready }
        let client = try XCTUnwrap(player.clientName)

        let manager = ConnectionManager(linking: graph)
        graph.onChange = { manager.graphChanged() }
        manager.attach(client: client, routing: ChannelRouting(channels: [["dest:in1"], ["dest:in2"]]))
        XCTAssertTrue(manager.failures.isEmpty, "\(manager.failures)")
        // The name is the one JACK really gave: the ports of the player are in the graph under it.
        XCTAssertTrue(graph.bridge.getPorts().map(\.id).contains("\(client):out_1"), "no port \(client):out_1")
        XCTAssertEqual(graph.destinations(of: "\(client):out_1"), ["dest:in1"])
        XCTAssertEqual(graph.destinations(of: "\(client):out_2"), ["dest:in2"])

        func peaks() async -> (Float, Float) {
            _ = meter.takeMeterPeak(channel: 0); _ = meter.takeMeterPeak(channel: 1)   // what came before
            await sleep(0.4)
            return (meter.takeMeterPeak(channel: 0) ?? -1, meter.takeMeterPeak(channel: 1) ?? -1)
        }

        player.send(.play)
        await sleep(0.3)
        var p = await peaks()
        XCTAssertEqual(p.0, 0.5, accuracy: 0.06, "channel 1 reaches dest:in1")
        XCTAssertEqual(p.1, 0.25, accuracy: 0.06, "channel 2 reaches dest:in2")

        // The two channels swapped: the levels follow, so the channels are really where the matrix says.
        manager.update(routing: ChannelRouting(channels: [["dest:in2"], ["dest:in1"]]))
        p = await peaks()
        XCTAssertEqual(p.0, 0.25, accuracy: 0.06)
        XCTAssertEqual(p.1, 0.5, accuracy: 0.06)

        // One channel disconnected: its input hears nothing.
        manager.update(routing: ChannelRouting(channels: [[], ["dest:in1"]]))
        p = await peaks()
        XCTAssertEqual(p.0, 0.25, accuracy: 0.06)
        XCTAssertLessThan(p.1, 0.001)

        // A destination that is not there yet is connected when it appears.
        manager.update(routing: ChannelRouting(channels: [["dest:in2", "Ghost:in1"], ["dest:in1"]]))
        XCTAssertEqual(manager.missingPorts, ["Ghost:in1"])
        let ghost = JackBridgeWrapper()
        try ghost.open(clientName: "Ghost")
        XCTAssertEqual(ghost.registerMeterPorts(count: 1), 1)
        await waitFor("the port is connected once it appears") { graph.destinations(of: "\(client):out_1").contains("Ghost:in1") }
        XCTAssertTrue(manager.missingPorts.isEmpty)

        player.stop()
        var exited = false
        player.onEvent = { if case .exited = $0 { exited = true } }
        await waitFor("the player ends") { exited }
        manager.detach()
        ghost.close()
        meter.close()
    }
}
