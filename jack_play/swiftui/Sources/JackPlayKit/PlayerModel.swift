// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import MeterKit
import Observation
import WaveformKit

// MARK: What the model needs, so that tests can give fakes

/// What the model needs from the program that plays. `PlayerProcess` is the real one.
@MainActor
public protocol PlayerRunner: AnyObject {
    var onEvent: ((PlayerEvent) -> Void)? { get set }
    /// The name of its JACK client, once it runs.
    var clientName: String? { get }
    var isRunning: Bool { get }
    func start() throws
    func send(_ control: PlayerControl)
    func stop(grace: TimeInterval)
    func terminate()
}

extension PlayerProcess: PlayerRunner {}

/// What the model needs from the JACK server: its state, the ports of the system, the connections and the transport.
/// `PlaybackGraph` is the real one.
@MainActor
public protocol PlaybackServer: JackLinking {
    var isConnected: Bool { get }
    var sampleRate: Int? { get }
    /// The period of the server, in frames.
    var bufferSize: Int? { get }
    /// The playback ports of the system, where a file goes the first time.
    var playbackPorts: [String] { get }
    /// Called when the graph has changed or the server has come or gone.
    var onChange: (() -> Void)? { get set }
    func transportStart()
    func transportPause()
    func transportStop()
    func transportLocate(frame: UInt32)
}

// MARK: The model

/// Why nothing plays.
public enum PlayerFailure: Equatable, Sendable {
    /// There is no JACK server: the player is started as soon as there is one.
    case noJack
    /// The jack_play program is not where the application keeps it.
    case noPlayer
    /// The file cannot be opened as a sound file.
    case cannotOpenFile(String)
    /// The program has ended without being asked to.
    case playerEnded(status: Int32)
}

/// The file that is open.
public struct OpenFile: Equatable, Sendable {
    public let url: URL
    public let info: SoundFileInfo
    public let key: FileKey
}

/// Everything the window shows, and what the buttons do. It opens a file, starts `jack_play` for it, keeps what the
/// program says (position, levels), connects its outputs where the matrix says and remembers that for the file.
@MainActor
@Observable
public final class PlayerModel {
    public enum Phase: Equatable, Sendable {
        /// No file.
        case empty
        /// The program is starting: its ports are not there yet.
        case starting
        /// Playing, paused or at the end, as the program says.
        case running(PlayerState)
        case failed(PlayerFailure)
    }

    // What is shown
    public private(set) var file: OpenFile?
    public private(set) var phase: Phase = .empty
    /// Frame of the file the player is at.
    public private(set) var position: Int64 = 0
    public private(set) var meters: [ChannelMeter] = []
    /// Whether the levels are measured. Off, the program is told so (in the mode where the application drives it) and the
    /// meters stay empty: nothing is measured, nothing is shown.
    public var metersEnabled = true {
        didSet {
            guard metersEnabled != oldValue else { return }
            if mode == .independent {
                runner?.send(.levels(metersEnabled))
                standby?.runner.send(.levels(metersEnabled))
            }
            if !metersEnabled {
                tracker.reset()
                meters = []
            }
        }
    }
    public private(set) var routing = ChannelRouting.empty(channels: 0)
    /// The warnings the program wrote ("disk thread late"), since the file was opened.
    public private(set) var warnings = 0
    public private(set) var lastWarning: String?
    /// Destinations of the routing that are not in the graph.
    public private(set) var missingPorts: Set<String> = []
    /// The rate the program says the server has (it may differ from the file's).
    public private(set) var serverRate: Double?
    public let waveform = WaveformModel()

    // What the person sets
    public private(set) var settings: PlayerSettings
    public private(set) var mode: PlayerCommand.Mode
    /// In the mode that follows the transport: whether the buttons of the window drive it. Off, the window only watches.
    public var commandsTransport = true
    /// Connect the outputs when the player starts. Off, nothing is connected until the matrix says so.
    public var autoConnect = true

    // The file after this one (the playlist says which), and the program that is ready to play it.
    /// The file that comes next. The application starts a second program for it, paused and with its ports connected, while this
    /// one plays (only when it plays on its own: a transport that is followed decides by itself). At the end of this file the second
    /// program takes over with a `play`, so that the files follow each other with a gap of the same short length every time.
    public var nextFile: URL? {
        didSet { if nextFile != oldValue { refreshStandby() } }
    }
    /// The place of the file that plays in the playlist, from 1, and the place of the next one: they are in the names of the programs
    /// in JACK, "02 of 12 - jack_play" (see `PlayerCommand.programName`). nil when the playlist has one file only. A program keeps
    /// the name it was started with, so the place that is in it is the one the file had then.
    public var currentNumber: Int?
    public var nextNumber: Int? { didSet { if nextNumber != oldValue { renameStandbyIfNeeded() } } }
    /// The number of files of the playlist, which is in the names too. It is read when a program is started: the one that
    /// plays keeps the size the list had then, and the next one is made again when the size changes.
    public var listCount: Int? { didSet { if listCount != oldValue { renameStandbyIfNeeded() } } }
    private func renameStandbyIfNeeded() {
        guard let s = standby, s.number != standbyNumber || s.count != listCount else { return }
        stopStandby()      // a program cannot be renamed: the one with the right name is made when the other has left
        refreshStandby()
    }
    /// The place of the next file: the one the playlist says, else the one after the file that plays (the two programs live
    /// together, so they need two names).
    private var standbyNumber: Int { nextNumber ?? ((currentNumber ?? 1) + 1) }
    /// Called once when the file has been played to its end, in the mode where the application plays on its own.
    @ObservationIgnored public var onFileEnded: (() -> Void)?
    /// The next file is ready to start at once.
    public var nextIsReady: Bool { standby?.ready == true && standby?.file.url == nextFile }

    // Collaborators
    private let server: PlaybackServer
    private let store: ConnectionStore
    private let makeRunner: @MainActor (PlayerCommand) -> PlayerRunner?
    private var manager: ConnectionManager
    private var runner: PlayerRunner?
    private var tracker = LevelTracker()
    private var lastLevelAt = Date.distantPast
    @ObservationIgnored private var decay: Task<Void, Never>?
    private var usesDefaultRouting = true
    /// The program of the next file.
    private struct Standby {
        let file: OpenFile
        let runner: PlayerRunner
        let manager: ConnectionManager
        let routing: ChannelRouting
        var ready = false
        var serverRate: Double?
        var number: Int?
        var count: Int?
    }
    private var standby: Standby?
    /// A program of the next file that was asked to leave and has not left yet.
    private var standbyLeaving: PlayerRunner?
    /// The program of the next file has been told to start at the end of this one.
    private var nextIsArmed = false
    private var endReported = false
    /// The program that was asked to leave and has not left yet. The next one waits for it: they carry the same name,
    /// and JACK would call the second one "name-01" while the first is still in the graph.
    private var leaving: PlayerRunner?
    private var queuedLaunch: (() -> Void)?
    /// The end of the file has been met in the mode that follows the transport, and the transport stopped.
    private var endHandled = false

    private struct Restart {
        let frame: Int64
        let playing: Bool
    }

    /// - Parameters:
    ///   - makeRunner: starts nothing: it only builds the program for a command. nil means the program is not found.
    public init(server: PlaybackServer, store: ConnectionStore, settings: PlayerSettings = PlayerSettings(), mode: PlayerCommand.Mode = .independent,
                makeRunner: @escaping @MainActor (PlayerCommand) -> PlayerRunner?) {
        self.server = server
        self.store = store
        self.settings = settings
        self.mode = mode
        self.makeRunner = makeRunner
        manager = ConnectionManager(linking: server)
        server.onChange = { [weak self] in self?.serverChanged() }
    }

    // MARK: Reading the state

    public var isPlaying: Bool { phase == .running(.playing) }
    public var hasEnded: Bool { phase == .running(.ended) }
    public var isRunning: Bool { if case .running = phase { return true }; return false }
    public var duration: TimeInterval { file?.info.duration ?? 0 }
    public var positionSeconds: TimeInterval {
        guard let info = file?.info, info.sampleRate > 0 else { return 0 }
        return Double(position) / info.sampleRate
    }
    /// Where the player is, from 0 to 1.
    public var fraction: Double {
        guard let frames = file?.info.frames, frames > 0 else { return 0 }
        return min(max(Double(position) / Double(frames), 0), 1)
    }
    /// The buttons act: not when the window only watches a transport that another program drives.
    public var canCommand: Bool { isRunning && (mode == .independent || commandsTransport) }
    /// The command as a person would type it, for the "command line" sheet.
    public var commandLine: String? { file.map { command(for: $0.url, frame: nil, number: currentNumber).display() } }
    /// A destination of the routing is connected twice over: several channels feed the same port.
    public var summedPorts: Set<String> { routing.summedPorts }

    /// Where the channels of a file go: the routing that is in use if it is the file that is open, else the one kept for the
    /// file, else the one it gets the first time (the first outputs of the system). For the list, which shows it.
    public func routing(for url: URL, channels: Int) -> ChannelRouting {
        if let file, file.url == url, file.info.channels == channels { return routing }
        return store.routing(for: FileKey(url: url), channels: channels)
            ?? DefaultRouting.make(channels: channels, playbackPorts: server.playbackPorts)
    }

    // MARK: Opening

    /// Opens a file, and starts the program for it, which plays at once when `play` is set. The one that was open is closed.
    public func open(_ url: URL, play: Bool = false) {
        closeFile()
        let info: SoundFileInfo
        do { info = try SoundFile.probe(url) } catch {
            phase = .failed(.cannotOpenFile("\(error)"))
            return
        }
        let key = FileKey(url: url)
        file = OpenFile(url: url, info: info, key: key)
        position = 0
        warnings = 0
        lastWarning = nil
        tracker.reset()
        meters = []
        waveform.load { try SoundFile(url: url) }
        chooseRouting()
        launch(frame: nil, playing: play)
        startDecay()
    }

    public func closeFile() {
        queuedLaunch = nil
        endReported = false
        decay?.cancel(); decay = nil
        stopRunner()
        waveform.cancel()
        file = nil
        phase = .empty
        position = 0
        meters = []
        tracker.reset()
        routing = .empty(channels: 0)
        missingPorts = []
    }

    // MARK: The buttons

    public func play() {
        guard canCommand else { return }
        switch mode {
        case .independent: runner?.send(.play)
        case .followTransport:
            // At the end of the file the transport was paused where it was: it starts again from the beginning.
            if hasEnded { server.transportLocate(frame: 0) }
            server.transportStart()
        }
    }

    public func pause() {
        guard canCommand else { return }
        switch mode {
        case .independent:
            cancelNextStart()
            runner?.send(.pause)
        case .followTransport: server.transportPause()
        }
    }

    /// The next program was told to start at the end of this file, which is no longer where it was (pause, seek): it waits again.
    private func cancelNextStart() {
        guard nextIsArmed else { return }
        nextIsArmed = false
        standby?.runner.send(.pause)
    }

    public func togglePlay() { isPlaying ? pause() : play() }

    /// Pauses and goes back to the start of the file.
    public func stop() {
        guard canCommand else { return }
        switch mode {
        case .independent:
            runner?.send(.pause)
            seek(frame: 0)
        case .followTransport:
            server.transportStop()
        }
    }

    /// Goes to a position in the file, from 0 to 1.
    public func seek(fraction: Double) {
        guard let frames = file?.info.frames, frames > 0 else { return }
        seek(frame: Int64(min(max(fraction, 0), 1) * Double(frames - 1)))
    }

    public func seek(seconds: TimeInterval) {
        guard let rate = file?.info.sampleRate else { return }
        seek(frame: Int64(max(seconds, 0) * rate))
    }

    /// Goes to a frame of the file.
    public func seek(frame: Int64) {
        guard canCommand, let info = file?.info else { return }
        let target = min(max(frame, 0), max(info.frames - 1, 0))
        position = target
        switch mode {
        case .independent:
            cancelNextStart()
            runner?.send(.seek(target))
        case .followTransport:
            // The transport counts frames of the server, the file frames of its own rate.
            let rate = serverRate ?? Double(server.sampleRate ?? Int(info.sampleRate))
            let serverFrame = Double(target) * rate / info.sampleRate
            if serverFrame < Double(UInt32.max) { server.transportLocate(frame: UInt32(serverFrame)) }
        }
    }

    // MARK: Settings

    /// Changes the options of the program. It is started again where it was, and goes on playing if it was.
    public func update(settings new: PlayerSettings) {
        guard new != settings else { return }
        settings = new
        relaunchKeepingPlace()
    }

    public func set(mode new: PlayerCommand.Mode) {
        guard new != mode else { return }
        mode = new
        relaunchKeepingPlace()
    }

    // MARK: Outputs

    /// The matrix: connects or disconnects a channel and a port, and remembers it for the file.
    public func toggle(channel: Int, port: String) {
        guard let file else { return }
        var r = routing
        r.toggle(channel: channel, port: port)
        setRouting(r, for: file)
    }

    /// Replaces the whole routing (a preset of the matrix).
    public func setRouting(_ new: ChannelRouting) {
        guard let file else { return }
        setRouting(new, for: file)
    }

    /// The first outputs of the system for each channel (the preset of the matrix).
    public func presetFirstOutputs() {
        guard let file else { return }
        setRouting(DefaultRouting.make(channels: file.info.channels, playbackPorts: server.playbackPorts), for: file)
    }

    private func setRouting(_ new: ChannelRouting, for file: OpenFile) {
        routing = new.resized(to: file.info.channels)
        usesDefaultRouting = false
        store.remember(routing, for: file.key)
        manager.update(routing: routing)
        missingPorts = manager.missingPorts
    }

    // MARK: Running the program

    private func command(for url: URL, frame: Int64?, number: Int?, fileRate: Double? = nil) -> PlayerCommand {
        var s = settings
        s.clientName = s.programName(number: number, of: listCount)
        return PlayerCommand(file: url, settings: s, mode: mode, initialFrame: frame, serverPeriod: server.bufferSize,
                             fileRate: fileRate ?? file?.info.sampleRate)
    }

    private func chooseRouting() {
        guard let file else { return }
        if let stored = store.routing(for: file.key, channels: file.info.channels) {
            routing = stored
            usesDefaultRouting = false
        } else {
            routing = DefaultRouting.make(channels: file.info.channels, playbackPorts: server.playbackPorts)
            usesDefaultRouting = true
        }
    }

    private func launch(frame: Int64?, playing: Bool) {
        guard let file else { return }
        guard server.isConnected else {
            phase = .failed(.noJack)
            return
        }
        if leaving != nil {
            phase = .starting
            queuedLaunch = { [weak self] in self?.launch(frame: frame, playing: playing) }
            return
        }
        guard let runner = makeRunner(command(for: file.url, frame: frame, number: currentNumber)) else {
            phase = .failed(.noPlayer)
            return
        }
        runner.onEvent = { [weak self, weak runner] event in
            guard let self, let runner, self.runner === runner else { return }
            self.handle(event, playAtReady: playing)
        }
        self.runner = runner
        phase = .starting
        do { try runner.start() } catch {
            self.runner = nil
            phase = .failed(.noPlayer)
        }
    }

    private func stopRunner() {
        manager.detach()
        queuedLaunch = nil
        let old = runner
        runner = nil   // before the program of the next file leaves: its exit must not make another one for a player that is gone
        stopStandby()
        guard let old else { return }
        guard old.isRunning else { old.onEvent = nil; return }
        leaving = old
        old.onEvent = { [weak self, weak old] event in
            guard case .exited = event, let self, let old, self.leaving === old else { return }
            self.leaving = nil
            old.onEvent = nil
            let next = self.queuedLaunch
            self.queuedLaunch = nil
            next?()
        }
        old.stop(grace: 1)
    }

    private func relaunchKeepingPlace() {
        guard file != nil else { return }
        let plan = Restart(frame: position, playing: isPlaying)
        stopRunner()
        launch(frame: plan.frame, playing: plan.playing)
    }

    private func handle(_ event: PlayerEvent, playAtReady: Bool) {
        switch event {
        case .ready(_, _, let serverRate, _):
            self.serverRate = serverRate
            phase = .running(.paused)
            if let client = runner?.clientName {
                manager.attach(client: client, routing: autoConnect ? routing : .empty(channels: file?.info.channels ?? 0))
                missingPorts = manager.missingPorts
            }
            if mode == .independent, !metersEnabled { runner?.send(.levels(false)) }
            if playAtReady { mode == .independent ? runner?.send(.play) : server.transportStart() }
            refreshStandby()
        case .position(let frame, let state):
            position = min(frame, file?.info.frames ?? frame)
            phase = .running(state)
            // The transport is shared and goes on after the end of the file: when the window drives it, it stops there.
            if mode == .followTransport, state == .ended, commandsTransport, !endHandled {
                endHandled = true
                server.transportPause()
            } else if state != .ended {
                endHandled = false
            }
            if state == .ended, mode == .independent {
                if !endReported { endReported = true; onFileEnded?() }
            } else {
                endReported = false
            }
        case .levels(let peaks):
            guard metersEnabled else { return }
            lastLevelAt = Date()
            tracker.update(peaks: peaks)
            meters = tracker.meters
        case .warning(let text):
            warnings += 1
            lastWarning = text
        case .endAnnounced(let time):
            // The end of this file is known to the frame: the next one starts then, with no gap.
            if mode == .independent, nextIsReady, !nextIsArmed, isPlaying, let s = standby {
                s.runner.send(.playAt(time))
                nextIsArmed = true
                }
        case .client, .message:
            break
        case .exited(let status, _):
            manager.detach()
            runner = nil
            // The program dies with the server, and the two news come in any order: with no server, the server is the reason.
            if file != nil { phase = server.isConnected ? .failed(.playerEnded(status: status)) : .failed(.noJack) }
        }
    }

    /// The graph has changed, or the server has come or gone.
    private func serverChanged() {
        manager.graphChanged()
        standby?.manager.graphChanged()
        missingPorts = manager.missingPorts
        guard file != nil else { return }
        if usesDefaultRouting, routing.connectedChannels == 0, !server.playbackPorts.isEmpty, let file {
            routing = DefaultRouting.make(channels: file.info.channels, playbackPorts: server.playbackPorts)
            manager.update(routing: routing)
        }
        // The program could not start without a server: it starts now.
        if phase == .failed(.noJack), server.isConnected { launch(frame: nil, playing: false) }
        // The server has gone: the program goes with it.
        if !server.isConnected {
            if runner != nil {
                stopRunner()
                phase = .failed(.noJack)
            } else if case .failed(.playerEnded) = phase {
                // The program was heard to end before the server was heard gone: it was the server that took it away,
                // and it starts again when the server is back. (A program that ends while the server stays is not started
                // again: that would be a loop.)
                stopStandby()
                phase = .failed(.noJack)
            }
        }
    }

    // MARK: The next file

    /// Starts, keeps or stops the program of the next file, as the state of the player allows.
    private func refreshStandby() {
        guard mode == .independent, runner != nil, isRunning, server.isConnected, let url = nextFile, !settings.loop else {
            stopStandby()
            return
        }
        if let s = standby, s.file.url == url { return }
        stopStandby()
        // The old program may have left at once, and made the new one on its way out.
        if let s = standby, s.file.url == url { return }
        // A program of the same name that is still leaving: this one starts when it is gone.
        if standbyLeaving != nil { return }
        guard let info = try? SoundFile.probe(url) else { return }
        let key = FileKey(url: url)
        let file = OpenFile(url: url, info: info, key: key)
        let routing = store.routing(for: key, channels: info.channels) ?? DefaultRouting.make(channels: info.channels, playbackPorts: server.playbackPorts)
        let number = standbyNumber
        // A program that is still leaving under the name this one would have: it starts when that one is gone.
        if let name = leaving?.clientName, name == settings.programName(number: number, of: listCount) { return }
        guard let runner = makeRunner(command(for: url, frame: nil, number: number, fileRate: info.sampleRate)) else { return }
        let next = Standby(file: file, runner: runner, manager: ConnectionManager(linking: server), routing: routing, number: number, count: listCount)
        runner.onEvent = { [weak self, weak runner] event in
            guard let self, let runner, self.standby?.runner === runner else { return }
            self.handleStandby(event)
        }
        standby = next
        do { try runner.start() } catch { standby = nil }
    }

    private func handleStandby(_ event: PlayerEvent) {
        guard var s = standby else { return }
        switch event {
        case .ready(_, _, let serverRate, _):
            s.ready = true
            s.serverRate = serverRate
            standby = s
            if !metersEnabled { s.runner.send(.levels(false)) }
            if let client = s.runner.clientName {
                s.manager.attach(client: client, routing: autoConnect ? s.routing : .empty(channels: s.file.info.channels))
            }
        case .exited:
            s.manager.detach()
            standby = nil
        default:
            break
        }
    }

    private func stopStandby() {
        nextIsArmed = false
        guard let s = standby else { return }
        standby = nil
        s.manager.detach()
        guard s.runner.isRunning else { s.runner.onEvent = nil; return }
        standbyLeaving = s.runner
        s.runner.onEvent = { [weak self, weak runner = s.runner] event in
            guard case .exited = event, let self, let runner, self.standbyLeaving === runner else { return }
            self.standbyLeaving = nil
            runner.onEvent = nil
            self.refreshStandby()
        }
        s.runner.stop(grace: 1)
    }

    /// Goes on with the next file: its program, which is ready, takes the place of this one and starts. False when it is not ready
    /// (or there is no next file): the caller opens the file the usual way.
    @discardableResult
    public func advanceToNext(play: Bool) -> Bool {
        guard mode == .independent, nextIsReady, let s = standby else { return false }
        let nextWasArmed = nextIsArmed
        nextIsArmed = false
        // This program leaves (its connections go with it) ...
        let old = runner
        manager.detach()
        runner = nil
        old?.onEvent = nil
        if let old, old.isRunning {
            leaving = old
            old.onEvent = { [weak self, weak old] event in
                guard case .exited = event, let self, let old, self.leaving === old else { return }
                self.leaving = nil
                old.onEvent = nil
                self.refreshStandby()
            }
            old.stop(grace: 1)
        }
        // ... and the other one is the player.
        standby = nil
        manager = s.manager
        runner = s.runner
        file = s.file
        routing = s.routing
        usesDefaultRouting = store.routing(for: s.file.key, channels: s.file.info.channels) == nil
        currentNumber = s.number
        serverRate = s.serverRate
        position = 0
        warnings = 0
        lastWarning = nil
        endReported = false
        endHandled = false
        tracker.reset()
        meters = []
        missingPorts = manager.missingPorts
        waveform.load { try SoundFile(url: s.file.url) }
        let me = s.runner
        me.onEvent = { [weak self, weak me] event in
            guard let self, let me, self.runner === me else { return }
            self.handle(event, playAtReady: false)
        }
        // It has been told to start at the end of the file: it plays already, or does so at once.
        phase = .running(nextWasArmed && play ? .playing : .paused)
        if play, !nextWasArmed { me.send(.play) }
        return true
    }

    // MARK: Levels settle

    /// The meters fall by themselves when the program stops saying: it says nothing while it is paused, after one line with
    /// the zeros, which is not enough to bring them down.
    private func startDecay() {
        decay?.cancel()
        decay = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.decayTick()
            }
        }
    }

    /// One step of the fall, if the program has not said anything for a moment. Public so that tests need no clock.
    public func decayTick(now: Date = Date()) {
        guard meters.contains(where: { $0.level > 0.0005 || $0.peak > 0.0005 }), now.timeIntervalSince(lastLevelAt) > 0.1 else { return }
        tracker.update(peaks: Array(repeating: 0, count: meters.count), now: now)
        meters = tracker.meters
    }
}
