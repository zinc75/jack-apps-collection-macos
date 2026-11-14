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

    /// Another client with input ports (jack_capture, started by run_tests.sh) is listed with its ports, and the fake daemon says that
    /// it stands for Terminal: its icon comes from there. The hardware is the loudspeaker, not an application.
    func testTheIconOfAClientComesFromTheDaemon() async throws {
        let other = try XCTUnwrap(ProcessInfo.processInfo.environment["KLICK_TEST_JACK_OTHER"], "run_tests.sh starts another client")
        let (model, backend) = try makeModel()
        for _ in 0..<50 {
            model.refreshOutput()
            if backend.bundles[other] != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let groups = JackClientPorts.grouped(backend.ports)
        XCTAssertTrue(groups.contains { $0.name == other }, "the other client is listed")
        XCTAssertEqual(backend.bundles[other], "com.apple.Terminal")
        XCTAssertNil(backend.bundles["system"], "the hardware has no application")
        XCTAssertTrue(groups.first?.isPhysical ?? false, "the hardware comes first")
    }

    /// The server stops while Klick plays on it: within a refresh the first backend takes over, what played has stopped, the reason is
    /// shown and JACK stays the choice, to be tried again. A server of its own ("kltest2") is started and stopped here.
    func testItFallsBackWhenTheServerStops() async throws {
        let jackd = "/usr/local/bin/jackd"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: jackd), "needs jackd")
        let original = ProcessInfo.processInfo.environment["JACK_DEFAULT_SERVER"]
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", "kltest2", "-d", "dummy", "-r", "48000", "-p", "512"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer {
            if server.isRunning { server.terminate() }
            setenv("JACK_DEFAULT_SERVER", original ?? "", 1)
            if original == nil { unsetenv("JACK_DEFAULT_SERVER") }
        }
        setenv("JACK_DEFAULT_SERVER", "kltest2", 1)
        try await Task.sleep(for: .seconds(3))

        let jack = JackBackend()
        let player = Player(engine: try jack.makeEngine(), soundsDirectory: Self.sounds)
        let model = AppModel(player: player, store: MemoryStore(), backends: [OfflineBackend(), jack])
        XCTAssertEqual(model.backend.id, "jack")
        model.settings.backendID = "jack"   // the choice of the user, made earlier
        model.start(.simple)
        XCTAssertTrue(model.isPlaying)

        server.terminate()
        for _ in 0..<40 where !model.player.isBackendShutdown { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(model.player.isBackendShutdown, "the engine knows its server is gone")
        model.refreshOutput()
        XCTAssertEqual(model.backend.id, "offline", "the first backend takes over")
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.fallenBackFrom?.id, "jack")
        XCTAssertEqual(model.settings.backendID, "jack", "JACK stays the choice")
        XCTAssertTrue(model.errorMessage?.contains("JACK") ?? false, model.errorMessage ?? "no message")

        // The server comes back at another rate (a rate is fixed for the life of a server): trying again makes the engine at that rate.
        let second = Process()
        second.executableURL = URL(fileURLWithPath: jackd)
        second.arguments = ["-n", "kltest2", "-d", "dummy", "-r", "44100", "-p", "512"]
        second.standardOutput = FileHandle.nullDevice
        second.standardError = FileHandle.nullDevice
        try second.run()
        defer { if second.isRunning { second.terminate() } }
        try await Task.sleep(for: .seconds(3))
        model.switchBackend(to: "jack")
        XCTAssertEqual(model.backend.id, "jack", model.errorMessage ?? "")
        XCTAssertEqual(model.player.sampleRate, 44100, "the engine is made again at the rate of the new server")
        XCTAssertNil(model.fallenBackFrom)
        XCTAssertNil(model.errorMessage)
    }

    func testTheTransportIsFollowedOnlyWhenAsked() throws {
        let (model, backend) = try makeModel()
        XCTAssertFalse(JackBackend.followsTransport(model.settings), "off by default")
        backend.setFollowsTransport(true, model: model)
        XCTAssertTrue(JackBackend.followsTransport(model.settings))
        XCTAssertEqual(model.settings.option("transport", backend: "jack"), "1")
        backend.setFollowsTransport(false, model: model)
        XCTAssertFalse(JackBackend.followsTransport(model.settings))
        XCTAssertNil(model.settings.backendOptions["jack"], "an option that is off leaves no entry")
    }

    func testItWaitsForTheTransportWithoutAPressOnTheButton() throws {
        let (model, backend) = try makeModel()
        XCTAssertFalse(model.isPlaying)
        backend.setFollowsTransport(true, model: model)
        XCTAssertTrue(model.isPlaying, "armed by the option")
        XCTAssertEqual(model.player.transport.state, .waiting)
        XCTAssertFalse(model.showsLiveView, "waiting does not take the window over")
        model.togglePlayback()   // the user stops it: it is not armed again by the reading of the output
        model.refreshOutput()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.player.transport.state, .off)
        model.togglePlayback()
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.player.transport.state, .waiting)
        backend.setFollowsTransport(false, model: model)
        XCTAssertFalse(model.isPlaying, "without the option nothing waits")
    }

    func testTheTimebaseMasterIsAnOption() throws {
        let (model, backend) = try makeModel()
        XCTAssertFalse(JackBackend.isTimebaseMaster(model.settings))
        backend.setTimebaseMaster(true, model: model)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(JackBackend.isTimebaseMaster(model.settings))
        backend.setTimebaseMaster(false, model: model)
        XCTAssertFalse(JackBackend.isTimebaseMaster(model.settings))
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
