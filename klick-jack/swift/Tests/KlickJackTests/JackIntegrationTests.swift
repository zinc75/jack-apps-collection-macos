// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import XCTest
import KlickEngine
import KlickKit
@testable import KlickJack

/// The JACK backend on a JACK server of its own: run_tests.sh starts one ("kltest", dummy driver, 48000 Hz, blocks of 512) and sets
/// KLICK_TEST_JACK and JACK_DEFAULT_SERVER. Skipped otherwise: the tests never touch the server in use.
@MainActor
final class JackIntegrationTests: XCTestCase {
    static let sounds = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("klick/build/samples")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KLICK_TEST_JACK"] != nil, "needs a JACK server of its own: run run_tests.sh")
    }

    /// A model on the JACK backend (the offline one is the other on offer).
    func makeModel(options: [String: String] = [:]) throws -> (AppModel, JackBackend) {
        let backend = JackBackend()
        let store = MemoryStore()
        if !options.isEmpty {
            var s = ClickSettings()
            for (key, value) in options { s.setOption(key, value, backend: "jack") }
            store.data = try JSONEncoder().encode(s)
        }
        let player = Player(engine: try backend.makeEngine(), soundsDirectory: Self.sounds)
        return (AppModel(player: player, store: store, backends: [backend, OfflineBackend()]), backend)
    }

    func connected(_ backend: JackBackend) -> [String] { backend.ports.filter(\.isConnected).map(\.name).sorted() }

    func testTheServerIsRead() throws {
        let (model, backend) = try makeModel()
        XCTAssertEqual(model.backend.id, "jack")
        XCTAssertEqual(backend.availability, .available)
        model.refreshOutput()
        XCTAssertEqual(model.output.sampleRate, 48000)
        XCTAssertEqual(model.output.bufferFrames, 512)
        XCTAssertEqual(model.outputName, "jack:" + JackBackend.serverName, "the delay of the display is kept per server")
        XCTAssertTrue(backend.portName.hasPrefix("Klick") && backend.portName.hasSuffix(":out"), backend.portName)
        XCTAssertTrue(backend.ports.contains { $0.name == "system:playback_1" && $0.isPhysical })
    }

    func testItConnectsToTheFirstTwoOutputsAtStart() throws {
        let (model, backend) = try makeModel()
        model.refreshOutput()
        XCTAssertEqual(connected(backend), ["system:playback_1", "system:playback_2"])
        model.refreshOutput()
        XCTAssertEqual(connected(backend).count, 2, "once")
    }

    func testTheConnectionAtStartCanBeTurnedOff() throws {
        let (model, backend) = try makeModel(options: ["autoconnect": "0"])
        XCTAssertFalse(JackBackend.autoconnects(model.settings))
        model.refreshOutput()
        XCTAssertEqual(connected(backend), [])
        backend.setAutoconnect(true, model: model)
        XCTAssertEqual(connected(backend), ["system:playback_1", "system:playback_2"], "turned on, it connects at once")
        XCTAssertTrue(JackBackend.autoconnects(model.settings))
        backend.setAutoconnect(false, model: model)
        XCTAssertEqual(model.settings.option("autoconnect", backend: "jack"), "0")
        XCTAssertEqual(connected(backend).count, 2, "turned off, what is connected stays")
    }

    func testAPortIsConnectedAndDisconnected() throws {
        let (model, backend) = try makeModel()
        model.refreshOutput()
        XCTAssertNil(backend.setConnected("system:playback_2", false, player: model.player))
        XCTAssertEqual(connected(backend), ["system:playback_1"])
        XCTAssertNil(backend.setConnected("system:playback_2", false, player: model.player), "already not connected: fine")
        XCTAssertNil(backend.setConnected("system:playback_2", true, player: model.player))
        XCTAssertEqual(connected(backend).count, 2)
        XCTAssertNotNil(backend.setConnected("system:no_such_port", true, player: model.player), "JACK refuses a port that is not there")
    }

    func testItPlaysAndTheBeatsArrive() async throws {
        let (model, _) = try makeModel()
        model.refreshOutput()
        model.settings.tempo = 120
        model.start(.simple)
        XCTAssertNil(model.errorMessage)
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(25))
            model.player.update()
        }
        XCTAssertGreaterThanOrEqual(model.player.beatCount, 2)
        model.stop()
    }

    func testSwitchingAwayFromJackAndBack() throws {
        let (model, backend) = try makeModel()
        model.refreshOutput()
        model.switchBackend(to: "offline")
        XCTAssertEqual(model.backend.id, "offline")
        XCTAssertEqual(model.settings.backendID, "offline")
        model.switchBackend(to: "jack")
        XCTAssertEqual(model.backend.id, "jack")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(connected(backend), ["system:playback_1", "system:playback_2"], "a new client, connected again")
        XCTAssertEqual(model.output.sampleRate, 48000)
    }
}

/// Settings kept in memory.
final class MemoryStore: SettingsStore {
    var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}
