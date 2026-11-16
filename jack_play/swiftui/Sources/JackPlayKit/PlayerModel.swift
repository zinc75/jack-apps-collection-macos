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

    // Collaborators
    private let server: PlaybackServer
    private let store: ConnectionStore
    private let makeRunner: @MainActor (PlayerCommand) -> PlayerRunner?
    private let manager: ConnectionManager
    private var runner: PlayerRunner?
    private var tracker = LevelTracker()
    private var lastLevelAt = Date.distantPast
    @ObservationIgnored private var decay: Task<Void, Never>?
    private var usesDefaultRouting = true

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
    public var commandLine: String? { file.map { command(for: $0.url, frame: nil).display() } }
    /// A destination of the routing is connected twice over: several channels feed the same port.
    public var summedPorts: Set<String> { routing.summedPorts }

    // MARK: Opening

    /// Opens a file, and starts the program for it. The one that was open is closed.
    public func open(_ url: URL) {
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
        launch(frame: nil, playing: false)
        startDecay()
    }

    public func closeFile() {
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
        case .followTransport: server.transportStart()
        }
    }

    public func pause() {
        guard canCommand else { return }
        switch mode {
        case .independent: runner?.send(.pause)
        case .followTransport: server.transportPause()
        }
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

    private func command(for url: URL, frame: Int64?) -> PlayerCommand {
        PlayerCommand(file: url, settings: settings, mode: mode, initialFrame: frame)
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
        guard let runner = makeRunner(command(for: file.url, frame: frame)) else {
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
        let old = runner
        runner = nil
        old?.onEvent = nil
        old?.stop(grace: 1)
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
            if playAtReady { mode == .independent ? runner?.send(.play) : server.transportStart() }
        case .position(let frame, let state):
            position = frame
            phase = .running(state)
        case .levels(let peaks):
            lastLevelAt = Date()
            tracker.update(peaks: peaks)
            meters = tracker.meters
        case .warning(let text):
            warnings += 1
            lastWarning = text
        case .message:
            break
        case .exited(let status, _):
            manager.detach()
            runner = nil
            if file != nil { phase = .failed(.playerEnded(status: status)) }
        }
    }

    /// The graph has changed, or the server has come or gone.
    private func serverChanged() {
        manager.graphChanged()
        missingPorts = manager.missingPorts
        guard file != nil else { return }
        if usesDefaultRouting, routing.connectedChannels == 0, !server.playbackPorts.isEmpty, let file {
            routing = DefaultRouting.make(channels: file.info.channels, playbackPorts: server.playbackPorts)
            manager.update(routing: routing)
        }
        // The program could not start without a server: it starts now.
        if phase == .failed(.noJack), server.isConnected { launch(frame: nil, playing: false) }
        // The server has gone: the program goes with it.
        if !server.isConnected, runner != nil {
            stopRunner()
            phase = .failed(.noJack)
        }
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
