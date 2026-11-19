// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import ZitaBridgeKit

/// The real programs, the real graph and the real wiring, on a JACK server of its own. The sound card of the server is the
/// dummy driver's: `system:capture_N` and `system:playback_N`. Skipped when a program or jackd is not there.
@MainActor
final class WiringIntegrationTests: XCTestCase {
    private func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    private func waitFor(_ what: String, timeout: Double = 10, _ condition: () -> Bool) async {
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

    func testTheWiringReachesThePortsOfTheRealPrograms() async throws {
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

        let graph = JackGraph()
        graph.excludedClients = ["zita-j2n", "zita-n2j"]
        graph.start()
        defer { graph.stop() }
        await waitFor("the graph connects to the server") { graph.isConnected }
        XCTAssertEqual(graph.sampleRate, 48000); XCTAssertEqual(graph.bufferSize, 256)
        XCTAssertEqual(graph.sources.first?.name, "system"); XCTAssertEqual(graph.destinations.first?.name, "system")
        XCTAssertEqual(graph.capturePorts.prefix(2), ["system:capture_1", "system:capture_2"])
        XCTAssertEqual(graph.playbackPorts.prefix(2), ["system:playback_1", "system:playback_2"])

        // The two programs, on a link of their own.
        let port = 20000 + Int.random(in: 0..<20000)
        var s = SendSettings(); s.address = "127.0.0.1"; s.port = port
        var r = ReceiveSettings(); r.address = "127.0.0.1"; r.port = port; r.channels = [1, 3]
        let receiver = ReceiverModel(settings: r, executable: n2j, jackServer: serverName)
        let sender = SenderModel(settings: s, executable: j2n, jackServer: serverName)
        receiver.start(); sender.start()
        defer { receiver.stop(); sender.stop() }

        // The programs' ports are not offered as somewhere to wire to, but the wiring sees them.
        await waitFor("the programs' ports exist") { graph.inputPorts().contains("zita-j2n:in_2") && graph.outputPorts().contains("zita-n2j:out_3") }
        graph.refresh()
        XCTAssertFalse(graph.sources.contains { $0.name == "zita-n2j" }); XCTAssertFalse(graph.destinations.contains { $0.name == "zita-j2n" })
        XCTAssertTrue(graph.outputPorts().contains("zita-n2j:out_1"), "the receiver names its ports after its channels: 1 and 3")
        XCTAssertFalse(graph.outputPorts().contains("zita-n2j:out_2"))

        let sending = WiringManager(direction: .send, linking: graph)
        let receiving = WiringManager(direction: .receive, linking: graph)
        var tx = ChannelWiring(); tx.toggle(channel: 1, port: "system:capture_1"); tx.toggle(channel: 2, port: "system:capture_2")
        var rx = ChannelWiring(); rx.toggle(channel: 1, port: "system:playback_1"); rx.toggle(channel: 3, port: "system:playback_2")
        sending.attach(client: "zita-j2n", channels: [1, 2], wiring: tx)
        receiving.attach(client: "zita-n2j", channels: [1, 3], wiring: rx)
        XCTAssertEqual(sending.failures, []); XCTAssertEqual(receiving.failures, [])

        // Read back from the server by a client that is not ours.
        let probe = JackBridgeWrapper()
        try probe.open(clientName: "probe")
        defer { probe.close() }
        let links = Set(probe.getConnections().map { "\($0.from)→\($0.to)" })
        XCTAssertTrue(links.contains("system:capture_1→zita-j2n:in_1"), "\(links)")
        XCTAssertTrue(links.contains("system:capture_2→zita-j2n:in_2"))
        XCTAssertTrue(links.contains("zita-n2j:out_1→system:playback_1"))
        XCTAssertTrue(links.contains("zita-n2j:out_3→system:playback_2"))

        // The matrix moves a connection.
        rx.toggle(channel: 3, port: "system:playback_2"); rx.toggle(channel: 3, port: "system:playback_1")
        receiving.update(wiring: rx)
        let after = Set(probe.getConnections().map { "\($0.from)→\($0.to)" })
        XCTAssertFalse(after.contains("zita-n2j:out_3→system:playback_2"))
        XCTAssertTrue(after.contains("zita-n2j:out_3→system:playback_1"), "two channels summed on one port")
        XCTAssertEqual(rx.summedPorts(in: [1, 3]), ["system:playback_1"])
    }
}
