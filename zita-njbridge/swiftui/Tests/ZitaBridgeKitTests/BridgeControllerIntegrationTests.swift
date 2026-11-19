// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import ZitaBridgeKit

/// The controller on the real programs and a JACK server of its own: arming, starting, wiring, restarting, remembering.
/// Skipped when a program or jackd is not there.
@MainActor
final class BridgeControllerIntegrationTests: XCTestCase {
    private func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    private func waitFor(_ what: String, timeout: Double = 12, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { await sleep(0.03) }
        XCTAssertTrue(condition(), what)
    }

    private func program(_ p: BridgeCommand.Program) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/\(p.rawValue)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("zita-njbridge/build/\(p.rawValue) is not built") }
        return url
    }

    private func links(_ probe: JackBridgeWrapper) -> Set<String> { Set(probe.getConnections().map { "\($0.from)→\($0.to)" }) }

    /// An automatic receiver starts with the channels the sender had last time (2 the first time). A sender of 4 channels is heard: the
    /// receiver is started again, once, with 4, and the 4 are remembered.
    func testAnAutomaticReceiverFollowsTheNumberOfChannelsOfTheSender() async throws {
        let n2j = try program(.receiver), j2n = try program(.sender)
        guard let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("jackd is not installed")
        }
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", serverName, "-d", "dummy", "-r", "48000", "-p", "256"]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        await sleep(2)
        setenv("JACK_DEFAULT_SERVER", serverName, 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }

        let suite = "zita-controller-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = 20000 + Int.random(in: 0..<20000)
        var stored = StoredBridgeSettings()
        stored.send.address = "127.0.0.1"; stored.send.port = port; stored.send.channels = 4
        stored.receive.address = "127.0.0.1"; stored.receive.port = port
        BridgeSettingsStore(defaults: defaults).save(stored)

        let controller = BridgeController(settingsStore: BridgeSettingsStore(defaults: defaults), wiringStore: WiringStore(defaults: defaults),
                                          helper: { $0 == .receiver ? n2j : j2n }, jackServer: serverName)
        controller.start()
        defer { controller.shutdown() }
        await waitFor("the graph connects") { controller.graph.isConnected }
        XCTAssertEqual(controller.receiver.settings.effectiveChannels, [1, 2])

        controller.toggleAll()
        // Heard with 4 channels while started with 2: started again with 4, and linked.
        await waitFor("the receiver takes the 4 channels") {
            controller.receiver.state == .linked && controller.receiver.runningSettings?.effectiveChannels == [1, 2, 3, 4]
        }
        XCTAssertEqual(controller.receiver.settings.knownSenderChannels, 4, "remembered for the next time")
        XCTAssertEqual(controller.receiver.sender?.channels, 4)
        XCTAssertFalse(controller.needsRestart(.receive), "it runs with what is set")
        XCTAssertTrue(controller.graph.outputPorts().contains("zita-n2j:out_4"))
        await waitFor("the settings are saved") { BridgeSettingsStore(defaults: defaults).load().receive.knownSenderChannels == 4 }

        // The next time it starts with 4 and is not started again.
        controller.toggleAll()
        await waitFor("everything stopped") { controller.receiver.state == .stopped && controller.sender.state == .stopped }
        controller.toggleAll()
        await waitFor("linked again") { controller.receiver.state == .linked }
        XCTAssertEqual(controller.receiver.runningSettings?.effectiveChannels, [1, 2, 3, 4])
        XCTAssertEqual(controller.receiver.sender?.channels, 4)
    }

    func testTheWholeLinkFromArmingToRestarting() async throws {
        let n2j = try program(.receiver), j2n = try program(.sender)
        guard let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("jackd is not installed")
        }
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", serverName, "-d", "dummy", "-r", "48000", "-p", "256"]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        await sleep(2)
        setenv("JACK_DEFAULT_SERVER", serverName, 1)
        defer { unsetenv("JACK_DEFAULT_SERVER") }

        let suite = "zita-controller-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = 20000 + Int.random(in: 0..<20000)
        var stored = StoredBridgeSettings()
        stored.send.address = "127.0.0.1"; stored.send.port = port
        stored.receive.address = "127.0.0.1"; stored.receive.port = port
        BridgeSettingsStore(defaults: defaults).save(stored)

        let controller = BridgeController(settingsStore: BridgeSettingsStore(defaults: defaults), wiringStore: WiringStore(defaults: defaults),
                                          helper: { $0 == .receiver ? n2j : j2n }, jackServer: serverName)
        controller.start()
        defer { controller.shutdown() }
        await waitFor("the graph connects") { controller.graph.isConnected }

        // The first time, each direction is wired to the sound card.
        await waitFor("the first wiring") { !controller.sendWiring.ports.isEmpty && !controller.receiveWiring.ports.isEmpty }
        XCTAssertEqual(controller.sendWiring.ports, [1: ["system:capture_1"], 2: ["system:capture_2"]])
        XCTAssertEqual(controller.receiveWiring.ports, [1: ["system:playback_1"], 2: ["system:playback_2"]])
        XCTAssertEqual(WiringStore(defaults: defaults).wiring(for: .receive), controller.receiveWiring, "and it is remembered")

        // The round button starts what is armed; the wiring is made as the ports appear.
        XCTAssertFalse(controller.anyArmedRuns)
        controller.toggleAll()
        await waitFor("both link up") { controller.receiver.state == .linked && controller.sender.state == .linked }
        let probe = JackBridgeWrapper()
        try probe.open(clientName: "probe")
        defer { probe.close() }
        await waitFor("the wiring is made") { self.links(probe).contains("zita-n2j:out_2→system:playback_2") && self.links(probe).contains("system:capture_1→zita-j2n:in_1") }
        XCTAssertTrue(controller.anyArmedRuns)

        // The matrix.
        controller.toggleWire(.receive, channel: 2, port: "system:playback_2")
        XCTAssertFalse(links(probe).contains("zita-n2j:out_2→system:playback_2"))
        controller.toggleWire(.receive, channel: 2, port: "system:playback_1")
        XCTAssertTrue(links(probe).contains("zita-n2j:out_2→system:playback_1"))

        // A setting that needs the program to start again says so, and the restart brings the wiring back.
        controller.receiver.settings.bufferMilliseconds = 25
        XCTAssertTrue(controller.needsRestart(.receive)); XCTAssertFalse(controller.needsRestart(.send))
        controller.restart(.receive)
        await waitFor("the receiver is back") { controller.receiver.state == .linked && !controller.needsRestart(.receive) }
        XCTAssertEqual(controller.receiver.runningSettings?.bufferMilliseconds, 25)
        await waitFor("the wiring is made again") { self.links(probe).contains("zita-n2j:out_2→system:playback_1") }

        // Disarming a direction stops it, and the round button then only concerns the other.
        controller.sendArmed = false
        await waitFor("the sender stopped") { controller.sender.state == .stopped }
        XCTAssertEqual(controller.armedDirections, [.receive])
        XCTAssertTrue(controller.receiver.state.isRunning)

        // Everything stops; what was set up is remembered.
        controller.toggleAll()
        await waitFor("the receiver stopped") { controller.receiver.state == .stopped }
        await sleep(0.4)
        XCTAssertFalse(links(probe).contains { $0.contains("zita-n2j") }, "its connections went with it")
        await waitFor("the settings are saved") { BridgeSettingsStore(defaults: defaults).load().receive.bufferMilliseconds == 25 }
        XCTAssertFalse(BridgeSettingsStore(defaults: defaults).load().sendArmed)
    }
}
