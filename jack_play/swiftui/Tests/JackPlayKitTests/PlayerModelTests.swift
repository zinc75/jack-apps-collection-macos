// SPDX-License-Identifier: GPL-3.0-or-later

import MeterKit
import XCTest
@testable import JackPlayKit

/// A program that plays, for the tests: it records what it is asked and says what the test makes it say.
@MainActor
final class FakeRunner: PlayerRunner {
    var onEvent: ((PlayerEvent) -> Void)?
    var clientName: String? { started ? "jack_play-000000004242" : nil }
    let command: PlayerCommand
    private(set) var controls: [PlayerControl] = []
    private(set) var started = false
    private(set) var stopped = false
    private(set) var terminated = false
    var failToStart = false

    init(command: PlayerCommand) { self.command = command }

    func start() throws {
        if failToStart { throw PlayerProcess.LaunchError.cannotStart("no") }
        started = true
    }
    func send(_ control: PlayerControl) { controls.append(control) }
    func stop(grace: TimeInterval) { stopped = true }
    func terminate() { terminated = true }

    func say(_ event: PlayerEvent) { onEvent?(event) }
    func ready(channels: Int = 2, fileRate: Double = 48000, serverRate: Double = 48000, frames: Int64 = 48000) {
        say(.ready(channels: channels, fileRate: fileRate, serverRate: serverRate, frames: frames))
    }
}

/// A JACK server in memory.
@MainActor
final class FakeServer: PlaybackServer {
    var isConnected = true
    var sampleRate: Int? = 48000
    var inputs: Set<String> = ["system:playback_1", "system:playback_2", "system:playback_3", "system:playback_4", "Carla:in1"]
    var links: Set<String> = []
    var onChange: (() -> Void)?
    private(set) var transport: [String] = []

    var playbackPorts: [String] { inputs.filter { $0.hasPrefix("system:") }.sorted() }
    func inputPorts() -> Set<String> { inputs }
    func destinations(of output: String) -> Set<String> {
        Set(links.compactMap { $0.hasPrefix(output + ">") ? String($0.dropFirst(output.count + 1)) : nil })
    }
    func connect(from output: String, to input: String) throws { links.insert("\(output)>\(input)") }
    func disconnect(from output: String, to input: String) throws { links.remove("\(output)>\(input)") }
    func transportStart() { transport.append("start") }
    func transportPause() { transport.append("pause") }
    func transportStop() { transport.append("stop") }
    func transportLocate(frame: UInt32) { transport.append("locate \(frame)") }
}

@MainActor
final class PlayerModelTests: XCTestCase {
    private var files: TestFiles!
    private var defaults: UserDefaults!
    private var runners: [FakeRunner] = []

    override func setUp() async throws {
        files = try TestFiles()
        let name = "jackplay-model-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        runners = []
    }

    private func make(server: FakeServer? = nil, mode: PlayerCommand.Mode = .independent, runnerFails: Bool = false,
                      settings: PlayerSettings = PlayerSettings()) -> (PlayerModel, FakeServer) {
        let server = server ?? FakeServer()
        let model = PlayerModel(server: server, store: ConnectionStore(defaults: defaults), settings: settings, mode: mode) { [unowned self] command in
            let r = FakeRunner(command: command)
            r.failToStart = runnerFails
            self.runners.append(r)
            return r
        }
        return (model, server)
    }

    private var runner: FakeRunner { runners.last! }

    private func wav(channels: Int = 2, format: Int = 0, frames: Int = 48000 * 4) throws -> URL {
        try files.write(TestFiles.all[format], channels: channels, frames: frames)
    }

    func testOpeningAFileStartsTheProgramPaused() throws {
        let (model, _) = make()
        XCTAssertEqual(model.phase, .empty)
        let url = try wav()
        model.open(url)
        XCTAssertEqual(model.phase, .starting)
        XCTAssertEqual(model.file?.info.channels, 2)
        XCTAssertEqual(model.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(runner.command.file, url)
        XCTAssertEqual(runner.command.mode, .independent)
        XCTAssertTrue(runner.started)
        runner.ready()
        XCTAssertEqual(model.phase, .running(.paused))
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.canCommand)
    }

    func testPlayingPausingAndStoppingAreCommands() throws {
        let (model, _) = make()
        model.open(try wav())
        model.play()   // the program is not ready yet: nothing is sent
        XCTAssertTrue(runner.controls.isEmpty)
        runner.ready()
        model.play()
        runner.say(.position(frame: 4800, state: .playing))
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.position, 4800)
        XCTAssertEqual(model.positionSeconds, 0.1, accuracy: 1e-9)
        model.togglePlay()
        XCTAssertEqual(runner.controls, [.play, .pause])
        model.stop()
        XCTAssertEqual(runner.controls.suffix(2), [.pause, .seek(0)])
        XCTAssertEqual(model.position, 0, "the cursor goes back at once")
    }

    func testSeekingIsInFramesOfTheFileAndMovesTheCursorAtOnce() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        model.seek(fraction: 0.5)
        XCTAssertEqual(runner.controls.last, .seek(Int64(0.5 * Double(48000 * 4 - 1))))
        model.seek(seconds: 3)
        XCTAssertEqual(runner.controls.last, .seek(144000))
        XCTAssertEqual(model.position, 144000)
        model.seek(frame: 99_999_999)   // beyond the end
        XCTAssertEqual(runner.controls.last, .seek(48000 * 4 - 1))
        model.seek(frame: -5)
        XCTAssertEqual(runner.controls.last, .seek(0))
        XCTAssertEqual(model.fraction, 0)
    }

    func testTheEndOfTheFileIsAState() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        runner.say(.position(frame: 192_000, state: .ended))
        XCTAssertTrue(model.hasEnded)
        XCTAssertEqual(model.fraction, 1)
        model.play()   // the program restarts from the beginning by itself
        XCTAssertEqual(runner.controls, [.play])
    }

    func testTheFirstTimeTheChannelsGoToTheFirstOutputs() throws {
        let (model, server) = make()
        model.open(try wav())
        XCTAssertEqual(model.routing.channels, [["system:playback_1"], ["system:playback_2"]])
        runner.ready()
        XCTAssertEqual(server.links, ["jack_play-000000004242:out_1>system:playback_1", "jack_play-000000004242:out_2>system:playback_2"])
    }

    func testAMonoFileGoesToBothSides() throws {
        let (model, server) = make()
        model.open(try wav(channels: 1))
        runner.ready(channels: 1)
        XCTAssertEqual(server.links.count, 2)
    }

    func testTheMatrixConnectsAndIsRememberedForTheFile() throws {
        let url = try wav()
        let (model, server) = make()
        model.open(url)
        runner.ready()
        model.toggle(channel: 0, port: "Carla:in1")
        XCTAssertTrue(server.links.contains("jack_play-000000004242:out_1>Carla:in1"))
        model.toggle(channel: 1, port: "system:playback_2")   // disconnect
        XCTAssertFalse(server.links.contains("jack_play-000000004242:out_2>system:playback_2"))
        // Another model, as after a restart: the same file comes back with its connections.
        let (again, server2) = make(server: FakeServer())
        again.open(url)
        XCTAssertEqual(again.routing.channels, [["system:playback_1", "Carla:in1"], []])
        runners.last!.ready()
        XCTAssertEqual(server2.links, ["jack_play-000000004242:out_1>Carla:in1", "jack_play-000000004242:out_1>system:playback_1"].reduce(into: Set<String>()) { $0.insert($1) })
    }

    func testAFileWithAnotherNumberOfChannelsHasItsOwnConnections() throws {
        let (model, _) = make()
        model.open(try wav(channels: 2))
        runner.ready()
        model.toggle(channel: 0, port: "Carla:in1")
        model.open(try wav(channels: 4, frames: 24000))
        XCTAssertEqual(model.routing.channels.count, 4)
        XCTAssertEqual(model.routing.channels[3], ["system:playback_4"])
        XCTAssertFalse(model.routing.contains(channel: 0, port: "Carla:in1"), "the first file's connections stay with it")
    }

    func testNothingIsConnectedWhenAutoConnectIsOff() throws {
        let (model, server) = make()
        model.autoConnect = false
        model.open(try wav())
        runner.ready()
        XCTAssertTrue(server.links.isEmpty)
        model.toggle(channel: 0, port: "system:playback_1")
        XCTAssertEqual(server.links.count, 1)
    }

    func testADestinationThatIsNotThereYetIsConnectedWhenItAppears() throws {
        let (model, server) = make()
        model.open(try wav())
        runner.ready()
        model.toggle(channel: 0, port: "Ghost:in1")
        XCTAssertEqual(model.missingPorts, ["Ghost:in1"])
        server.inputs.insert("Ghost:in1")
        server.onChange?()
        XCTAssertTrue(server.links.contains("jack_play-000000004242:out_1>Ghost:in1"))
        XCTAssertTrue(model.missingPorts.isEmpty)
    }

    func testTheLevelsAreTheMetersOfTheDisplay() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        runner.say(.levels([0.5, 0.25]))
        XCTAssertEqual(model.meters.count, 2)
        XCTAssertEqual(model.meters[0].level, IECScale.fraction(db: -6.0206), accuracy: 1e-3)
        XCTAssertGreaterThan(model.meters[0].level, model.meters[1].level)
        runner.say(.levels([1.0, 0]))
        XCTAssertTrue(model.meters[0].clipped)
    }

    func testTheMetersFallByThemselvesWhenTheProgramSaysNothing() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        runner.say(.levels([0.8, 0.8]))
        runner.say(.levels([0, 0]))   // the one line with the zeros
        let after = model.meters[0].level
        XCTAssertGreaterThan(after, 0, "one line is not enough to bring them down")
        var now = Date().addingTimeInterval(0.2)
        for _ in 0..<60 { model.decayTick(now: now); now = now.addingTimeInterval(0.033) }
        XCTAssertEqual(model.meters[0].level, 0, accuracy: 0.001)
    }

    func testAProgramThatEndsOnItsOwnIsAFailureAndTheFileStaysOpen() throws {
        let (model, _) = make()
        let url = try wav()
        model.open(url)
        runner.ready()
        runner.say(.exited(status: 1, requested: false))
        XCTAssertEqual(model.phase, .failed(.playerEnded(status: 1)))
        XCTAssertNotNil(model.file)
        XCTAssertFalse(model.canCommand)
        // Opening the file again starts a new program.
        model.open(url)
        XCTAssertEqual(runners.count, 2)
        XCTAssertEqual(model.phase, .starting)
    }

    func testAProgramThatCannotStart() throws {
        let (model, _) = make(runnerFails: true)
        model.open(try wav())
        XCTAssertEqual(model.phase, .failed(.noPlayer))
        let noProgram = PlayerModel(server: FakeServer(), store: ConnectionStore(defaults: defaults)) { _ in nil }
        noProgram.open(try wav())
        XCTAssertEqual(noProgram.phase, .failed(.noPlayer))
    }

    func testAFileThatCannotBeReadIsAFailureWithoutAProgram() throws {
        let (model, _) = make()
        let text = files.directory.appendingPathComponent("notes.txt")
        try "not a sound".write(to: text, atomically: true, encoding: .utf8)
        model.open(text)
        guard case .failed(.cannotOpenFile) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertNil(model.file)
        XCTAssertTrue(runners.isEmpty)
    }

    func testWithoutAServerTheProgramStartsWhenOneComes() throws {
        let server = FakeServer()
        server.isConnected = false
        let (model, _) = make(server: server)
        model.open(try wav())
        XCTAssertEqual(model.phase, .failed(.noJack))
        XCTAssertTrue(runners.isEmpty)
        XCTAssertNotNil(model.file, "the file is shown meanwhile")
        server.isConnected = true
        server.onChange?()
        XCTAssertEqual(model.phase, .starting)
        XCTAssertEqual(runners.count, 1)
        // The outputs were not known when the file was opened: the first ones of the system are chosen now.
        XCTAssertEqual(model.routing.channels, [["system:playback_1"], ["system:playback_2"]])
    }

    func testWhenTheServerStopsTheProgramStopsToo() throws {
        let (model, server) = make()
        model.open(try wav())
        runner.ready()
        server.isConnected = false
        server.onChange?()
        XCTAssertEqual(model.phase, .failed(.noJack))
        XCTAssertTrue(runner.stopped)
    }

    func testChangingTheLoopStartsTheProgramAgainWhereItWasAndPlaying() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        model.play()
        runner.say(.position(frame: 96000, state: .playing))
        let first = runner
        model.update(settings: PlayerSettings(loop: true))
        XCTAssertTrue(first.stopped)
        XCTAssertEqual(runners.count, 2)
        XCTAssertTrue(runner.command.settings.loop)
        XCTAssertEqual(runner.command.initialFrame, 96000)
        first.say(.position(frame: 1, state: .paused))   // a late word of the old program is not heard
        XCTAssertEqual(model.phase, .starting)
        runner.ready()
        XCTAssertEqual(runner.controls, [.play], "it was playing: it goes on")
        XCTAssertTrue(model.commandLine?.contains(" -l ") == true)
    }

    func testTheSameSettingsDoNotRestartAnything() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        model.update(settings: PlayerSettings())
        XCTAssertEqual(runners.count, 1)
    }

    func testClosingTheFileStopsTheProgram() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        model.closeFile()
        XCTAssertTrue(runner.stopped)
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.file)
        XCTAssertTrue(model.meters.isEmpty)
    }

    func testOpeningAnotherFileStopsTheFirstProgram() throws {
        let (model, _) = make()
        model.open(try wav())
        let first = runner
        first.ready()
        model.open(try wav(frames: 24000))
        XCTAssertTrue(first.stopped)
        XCTAssertEqual(runners.count, 2)
        first.say(.position(frame: 77, state: .playing))
        XCTAssertEqual(model.position, 0, "the first program is no longer heard")
    }

    func testWarningsAreCounted() throws {
        let (model, _) = make()
        model.open(try wav())
        runner.ready()
        runner.say(.warning("rju-play: disk thread late (3 < 1024)"))
        runner.say(.warning("rju-play: disk thread late (5 < 1024)"))
        XCTAssertEqual(model.warnings, 2)
        XCTAssertEqual(model.lastWarning, "rju-play: disk thread late (5 < 1024)")
    }

    func testTheWaveformIsReadForTheFile() async throws {
        let (model, _) = make()
        model.open(try wav())
        for _ in 0..<300 { if model.waveform.finishedPeaks != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.waveform.finishedPeaks?.channels, 2)
        XCTAssertEqual(model.waveform.finishedPeaks?.peak(channel: 0) ?? 0, 0.5, accuracy: 0.01)
    }
}

@MainActor
final class PlayerModelTransportTests: XCTestCase {
    private var files: TestFiles!
    private var defaults: UserDefaults!
    private var runners: [FakeRunner] = []

    override func setUp() async throws {
        files = try TestFiles()
        let name = "jackplay-transport-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    private func make() -> (PlayerModel, FakeServer) {
        let server = FakeServer()
        let model = PlayerModel(server: server, store: ConnectionStore(defaults: defaults), mode: .followTransport) { [unowned self] command in
            let r = FakeRunner(command: command)
            self.runners.append(r)
            return r
        }
        return (model, server)
    }

    func testFollowingTheTransportTheButtonsDriveIt() throws {
        let (model, server) = make()
        model.open(try files.write(TestFiles.all[0], channels: 2, frames: 48000 * 4))
        XCTAssertEqual(runners[0].command.mode, .followTransport)
        XCTAssertTrue(runners[0].command.arguments.contains("-t"))
        runners[0].ready()
        model.play()
        model.pause()
        model.stop()
        XCTAssertEqual(server.transport, ["start", "pause", "stop"])
        XCTAssertTrue(runners[0].controls.isEmpty, "nothing is sent to the program: the transport is the only command")
    }

    func testASeekIsAFrameOfTheServer() throws {
        let (model, server) = make()
        model.open(try files.write(TestFiles.all[1], channels: 2, frames: 44100 * 4))   // 44.1 kHz file, 48 kHz server
        runners[0].ready(fileRate: 44100, serverRate: 48000, frames: 176_400)
        model.seek(seconds: 2)   // 88200 frames of the file
        XCTAssertEqual(server.transport, ["locate 96000"], "2.000 s of the transport at 48 kHz")
        XCTAssertEqual(model.position, 88200)
    }

    func testTheWindowThatOnlyWatchesDoesNotCommand() throws {
        let (model, server) = make()
        model.commandsTransport = false
        model.open(try files.write(TestFiles.all[0], channels: 2, frames: 48000))
        runners[0].ready()
        XCTAssertFalse(model.canCommand)
        model.play()
        model.seek(frame: 100)
        XCTAssertTrue(server.transport.isEmpty)
        // It still shows what the transport does.
        runners[0].say(.position(frame: 500, state: .playing))
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(model.position, 500)
    }

    func testSwitchingModeStartsTheProgramAgain() throws {
        let (model, _) = make()
        model.open(try files.write(TestFiles.all[0], channels: 2, frames: 48000))
        runners[0].ready()
        model.set(mode: .independent)
        XCTAssertEqual(runners.count, 2)
        XCTAssertEqual(runners[1].command.mode, .independent)
        XCTAssertTrue(runners[0].stopped)
    }
}
