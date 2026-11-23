// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import MeterKit

/// What the recorder is waiting for before it writes, when it is armed.
public enum ArmedReason: Equatable, Sendable {
    /// Timemachine: listening, the file starts at the next press of the red button.
    case timemachine
    /// The JACK transport has to roll, or the server to go into freewheeling.
    case jack(String)
}

/// State of the window, and the control of the recording: it starts jack_capture, makes the connections it
/// cannot make itself, follows what it says and stops it.
@MainActor
@Observable
public final class RecorderModel {
    public var view: MainView = .recording {
        // The page of the channels is where a recording is set up: once seen, the red button may start one.
        didSet { if view == .channels { markConfigured() } }
    }
    /// False on the very first launch, until the page of the channels has been seen: the red button then leads
    /// there instead of recording with settings nobody has looked at.
    public var isConfigured: Bool { hub.isConfigured }
    public private(set) var phase: RecorderPhase = .configuration
    public private(set) var elapsed: TimeInterval = 0

    public var settings = CaptureSettings()
    /// What tells this session from the others: the window that shows it is opened for it.
    public let id: UUID
    /// What the windows share: the JACK client and the settings kept between two launches.
    public let hub: CaptureHub
    /// The JACK graph: sources for the matrix, state of the server.
    public var graph: JackGraph { hub.graph }
    /// Sample rate of the JACK server; 48 kHz while no server runs (what the estimates assume).
    public var sampleRate: Int { graph.sampleRate ?? 48_000 }

    // What the recording reports.
    public private(set) var armedReason: ArmedReason?
    /// The name of the file jack_capture writes, once it has said it.
    public private(set) var outputFile: String?
    public private(set) var status: CaptureStatus?
    /// The levels of the channels, from the console meter of jack_capture: what is recorded, not an estimate. They
    /// fall a little at a time, as a meter does; empty when the meters are switched off.
    public private(set) var meters: [ChannelMeter] = []
    public private(set) var bytesWritten: Int64 = 0
    /// What jack_capture complained about (a refused port, for instance), and connections that failed.
    public private(set) var warnings: [String] = []
    /// A failure to show to the user.
    public var errorMessage: String?

    /// The technical record of the recording that is done.
    public private(set) var summary: RecordingSummary?

    /// The file of the recording that is done.
    /// With rotation jack_capture says "name.wav" and writes "name.wav.00.wav", "name.wav.01.wav", …: the first part then.
    public var recordedURL: URL? {
        guard let name = outputFile else { return nil }
        let base = settings.folderURL.appendingPathComponent(name)
        return rotates ? (Self.rotatedParts(of: base).first ?? base) : base
    }

    /// Every file of the recording: one, or the parts of a rotated recording.
    public var recordedFiles: [URL] {
        guard let url = recordedURL else { return [] }
        guard rotates, let name = outputFile else { return [url] }
        let parts = Self.rotatedParts(of: settings.folderURL.appendingPathComponent(name))
        return parts.isEmpty ? [url] : parts
    }

    private var rotates: Bool { launched?.settings.rotatesFiles ?? settings.rotatesFiles }

    /// "<base>.NN.<ext>" in the folder of `base`, in order.
    static func rotatedParts(of base: URL, fileManager: FileManager = .default) -> [URL] {
        let folder = base.deletingLastPathComponent()
        let prefix = base.lastPathComponent + "."
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { name in
            guard name.hasPrefix(prefix) else { return false }
            let rest = name.dropFirst(prefix.count)
            guard let dot = rest.firstIndex(of: ".") else { return false }
            let number = rest[..<dot]
            return !number.isEmpty && number.allSatisfy(\.isNumber)
        }.sorted().map { folder.appendingPathComponent($0) }
    }

    private func totalSize() -> Int64 { recordedFiles.reduce(0) { $0 + (fileSize($1) ?? 0) } }

    public var command: CaptureCommand { CaptureCommand(settings: settings, sampleRate: sampleRate, inputConnections: graph.inputConnections) }
    public var bytesPerMinute: Double { RecordingEstimate.bytesPerSecond(settings, sampleRate: sampleRate) * 60 }
    /// Looks at the disk: call it when the view is built, not in a loop.
    public func nextFileName() -> String { FileNaming.nextName(settings) }
    public func availableBytes() -> Int64? { freeBytes?() ?? RecordingEstimate.availableBytes(at: settings.folderURL) }

    /// Seams for the tests: where the program is, and whether JACK is running.
    var executable: () -> URL? = { CaptureHelper.executableURL() }
    var jackIsAvailable: (() -> Bool)?

    private var runner: CaptureRunner?
    /// jack_capture said that the JACK server went away under it.
    private var jackLost = false
    private var lowDiskWarned = false
    /// Said to the person when they are not looking at the window: a title and a text. Set by the application (a notification of the system).
    public var notify: ((String, String) -> Void)?
    /// The seconds of recording that the disk can still take before it gets to the reserve; nil when unknown or when nothing is written.
    public private(set) var diskSecondsLeft: Double?
    /// The room left on the disk, for the tests.
    var freeBytes: (() -> Int64?)?
    /// What to do once jack_capture has ended: the application is waiting to quit.
    private var afterExit: (() -> Void)?
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    /// When the file started to be written, for what is drawn image by image (the clock is updated ten times a second).
    public var writingStartedAt: Date? { startedAt }
    private var initialSize: Int64?
    /// What the recording was started with: the settings and the command may change while it runs.
    private var launched: (settings: CaptureSettings, commandText: String, sampleRate: Int, date: Date)?

    /// A session of the application. `usesSavedSettings`: it starts from the settings of the last session (the first window at the launch); the others start from
    /// the defaults.
    public init(hub: CaptureHub, id: UUID = UUID(), usesSavedSettings: Bool = true) {
        self.hub = hub
        self.id = id
        if usesSavedSettings, let saved = hub.savedSettings() { settings = saved }
    }

    /// A session with a hub of its own: with `defaults`, the settings of the last session are read back, and `saveSettings()` keeps them. What the tests use.
    public convenience init(defaults: UserDefaults? = nil) {
        self.init(hub: CaptureHub(defaults: defaults), usesSavedSettings: true)
    }

    /// Reads saved settings, whichever version wrote them: a setting that was not saved takes its default, and
    /// the durations kept in minutes by an earlier version become seconds.
    static func decodeSettings(_ data: Data) -> CaptureSettings? {
        guard var saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSettings()))) as? [String: Any] else { return nil }
        for (old, new) in [("durationMinutes", "durationSeconds"), ("rotationMinutes", "rotationSeconds")] {
            if saved[new] == nil, let minutes = (saved[old] as? NSNumber)?.doubleValue {
                let seconds = max(1, Int((minutes * 60).rounded()))
                saved[new] = seconds
            }
            saved[old] = nil
        }
        let merged = base.merging(saved) { _, saved in saved }
        guard let merged = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(CaptureSettings.self, from: merged)
    }

    /// The page of the channels has been seen: from now on the red button records.
    public func markConfigured() { hub.markConfigured() }

    #if DEBUG
    /// Development aid: behaves as on a first launch, without touching what is saved.
    public func pretendFirstLaunch() { hub.pretendFirstLaunch() }
    #endif

    /// Notes the application behind each client of the graph that has one.
    public func rememberBundles() {
        for client in graph.clients {
            if let id = client.bundleID, settings.knownBundles[client.name] != id { settings.knownBundles[client.name] = id }
        }
    }

    /// Keeps the settings for the next launch. Call it when they change.
    public func saveSettings() { hub.save(settings) }

    /// The big red button: starts when idle, stops when something is running.
    public func toggleRecording() {
        #if DEBUG
        trace("toggleRecording called, phase=\(phase), jackConnected=\(graph.isConnected), executable=\(executable()?.path ?? "none")")
        defer { trace("  -> phase=\(phase), error=\(errorMessage ?? "none"), output=\(outputFile ?? "none")") }
        #endif
        switch phase {
        case .configuration, .done:
            if !isConfigured { view = .channels; return }
            if sourceCheck.isClean { start() } else { asksToConfirm = true }
        case .armed:
            if armedReason == .timemachine { beginWriting() } else { stop() }
        case .recording: stop()
        case .stopping: break
        }
    }

    /// Set when the red button was pressed while some channels would be silent: the window asks first.
    public var asksToConfirm = false

    /// The chosen sources against the graph now. Clean while no server runs: another message covers that.
    public var sourceCheck: SourceCheck {
        guard graph.isConnected else { return SourceCheck() }
        let available = Set(graph.clients.flatMap { client in (client.ports + client.inputs).map { client.fullName(of: $0) } })
        return SourceCheck(sources: settings.sources, channels: settings.channels, autoConnect: settings.autoConnect,
                           available: available, inputConnections: graph.inputConnections)
    }

    /// The warning was read: records all the same.
    public func startAnyway() {
        asksToConfirm = false
        start()
    }

    /// Something has been set up or recorded here: settings that are not the defaults, or a recording that is done.
    public var hasPreparedSettings: Bool { settings != CaptureSettings() || phase == .done }

    /// Back to a session with nothing in it: the defaults, and the page of the recording.
    public func resetToDefaults() {
        newRecording()
        settings = CaptureSettings()
    }

    /// Kept alive until jack_capture has closed the file when the session is dropped while it records: the recording must not be cut.
    private var keepAliveUntilExit: RecorderModel?

    /// Stops what is recorded now (the window of the session is closed over it, or the application leaves): the file is closed properly, and the session stays
    /// in memory until jack_capture is gone, or 25 seconds.
    public func stopNow() {
        guard runner != nil else { return }
        keepAliveUntilExit = self
        let before = afterExit
        afterExit = { [weak self] in before?(); self?.keepAliveUntilExit = nil }
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.keepAliveUntilExit = nil }
    }

    public func newRecording() {
        phase = .configuration
        view = .recording
        elapsed = 0
        resetReport()
    }

    #if DEBUG
    /// Development trace: one line per call in /tmp/jackcapture-trace.log.
    public func trace(_ line: String) {
        let text = "\(Date().formatted(date: .omitted, time: .standard)) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/jackcapture-trace.log") {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(toFile: "/tmp/jackcapture-trace.log", atomically: false, encoding: .utf8)
        }
    }
    #endif

    // MARK: Levels before the recording

    /// The idle page of the recording is on screen (set by the view): the levels are only listened to then.
    public var showsIdlePage = false
    /// The levels of the chosen sources, listened to by a JACK client of its own while nothing is recorded.
    public private(set) var idleMeters: [ChannelMeter] = []
    /// True while that client runs.
    public private(set) var isMonitoring = false
    private let monitor = LevelMonitor()
    private var tracker = LevelTracker()
    private var levelLoop: Task<Void, Never>?
    private var monitorRetryAt = Date.distantPast

    /// Starts reading the levels about thirty times a second; the client itself only exists when it is wanted.
    public func startLevelLoop() {
        guard levelLoop == nil else { return }
        levelLoop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                tick += 1
                self.levelTick(checkSetup: tick % 15 == 0)
            }
        }
    }

    private var monitorWanted: Bool {
        settings.monitorsLevels && settings.autoConnect && showsIdlePage && phase == .configuration && graph.isConnected
    }

    /// The channels and the ports to listen to, from the settings and the graph as they are now.
    private func monitorSetup() -> LevelMonitor.Setup? {
        var links: [LevelMonitor.Setup.Link] = []
        for channel in 0..<settings.channels where channel < settings.sources.count {
            for port in settings.sources[channel] {
                // A chosen input port stands for what feeds it.
                for source in graph.inputConnections[port] ?? [port] { links.append(.init(source: source, channel: channel)) }
            }
        }
        return links.isEmpty ? nil : LevelMonitor.Setup(channels: settings.channels, links: links)
    }

    private func levelTick(checkSetup: Bool) {
        guard monitorWanted, let wanted = monitorSetup() else {
            if monitor.isRunning || isMonitoring { stopMonitor() }
            return
        }
        if (checkSetup || !monitor.isRunning) && (monitor.setup != wanted || !monitor.isRunning) && Date() >= monitorRetryAt {
            // Its own name is taken by it: it must not count against it.
            let taken = graph.clientNames.subtracting(monitor.clientName.map { [$0] } ?? [])
            let name = JackGraph.freeName("\(settings.jackClientName) levels", taken: taken)
            tracker.reset()
            idleMeters = []
            isMonitoring = monitor.start(name: name, setup: wanted)
            if !isMonitoring { monitorRetryAt = Date().addingTimeInterval(2) }
        }
        guard let peaks = monitor.readPeaks() else { return }
        tracker.update(peaks: peaks)
        idleMeters = tracker.meters
    }

    private func stopMonitor() {
        monitor.stop()
        isMonitoring = false
        idleMeters = []
        tracker.reset()
    }

    /// The application quits: jack_capture does not outlive it.
    public func shutdown() {
        runner?.terminate()
    }

    /// Something is written, or waits to be.
    public var isBusy: Bool { phase.isLocked }
    /// A file is being written now: quitting would cut it.
    public var isWriting: Bool { phase == .recording || phase == .stopping }

    /// Stops the recording the way the red button does, and calls `completion` once jack_capture has closed
    /// the file (or after 25 s, whatever happens).
    public func stopForQuit(_ completion: @escaping () -> Void) {
        guard runner != nil else { completion(); return }
        var done = false
        let once = { if !done { done = true; completion() } }
        afterExit = once
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { once() }
    }

    // MARK: Start

    private func start() {
        stopMonitor()
        guard jackIsAvailable?() ?? graph.isConnected else {
            errorMessage = String(localized: "JACK n'est pas démarré. Démarrer le serveur JACK, puis recommencer.")
            return
        }
        guard let executable = executable() else {
            errorMessage = String(localized: "Le programme jack_capture est introuvable.")
            return
        }
        if let problem = FolderCheck.problem(for: settings.folderURL) {
            errorMessage = FolderCheck.message(problem, folder: settings.folderURL)
            return
        }
        // The disk keeps a reserve: a recording that would be stopped at once is not started.
        let reserve = DiskGuard.reserveBytes(gigabytes: settings.diskReserveGigabytes)
        if reserve > 0, let free = availableBytes(), free < reserve {
            errorMessage = String(localized: "Moins de \(settings.diskReserveGigabytes) Go libres sur ce disque : l'enregistrement s'arrêterait aussitôt. La réserve se règle dans la page Avancé.")
            return
        }
        // Under a fixed name two sessions would write the same file: one session, one file.
        let fixedTarget = settings.numbering ? nil : settings.folderURL.appendingPathComponent("\(settings.baseName).\(settings.format.fileExtension)")
        if let fixedTarget, !hub.reserve(fixedTarget, for: id) {
            errorMessage = String(localized: "Un autre enregistrement écrit déjà dans ce fichier. Changer le nom, ou activer la numérotation.")
            return
        }
        resetReport()
        // Another jack_capture may already hold the name: take a free one, as JACK would rename the client otherwise.
        graph.refresh()
        var run = settings
        run.clientName = JackGraph.freeName(settings.jackClientName, taken: graph.clientNames)
        let command = CaptureCommand(settings: run, sampleRate: sampleRate, inputConnections: graph.inputConnections)
        launched = (run, command.displayText, sampleRate, Date())
        let runner = CaptureRunner(executable: executable, arguments: command.arguments, directory: run.folderURL)
        runner.onEvent = { [weak self] in self?.handle($0) }
        runner.onExit = { [weak self] status, asked in self?.finished(status: status, asked: asked) }
        do {
            try runner.start()
        } catch {
            let reason: String
            if case CaptureRunner.LaunchError.cannotStart(let message) = error { reason = message } else { reason = error.localizedDescription }
            errorMessage = String(localized: "Impossible de lancer jack_capture : \(reason)")
            hub.release(for: id)
            return
        }
        self.runner = runner
        view = .recording

        if settings.timemachine {
            phase = .armed
            armedReason = .timemachine
        } else if settings.startMode != .immediately {
            phase = .armed
            armedReason = .jack(settings.startMode == .transport ? "transport" : "freewheel")
        } else {
            beginClock()
        }
        startTicker()

        // jack_capture connects a single source per channel itself; the others are connected here.
        if !command.connections.isEmpty {
            let pairs = command.connections.map { (source: $0.source, destination: $0.destination) }
            Task { [weak self] in
                guard let self else { return }
                let failed = await self.graph.connectWhenReady(pairs)
                if !failed.isEmpty {
                    self.warnings.append(String(localized: "Connexions refusées : \(failed.joined(separator: ", "))"))
                }
            }
        }
    }

    /// The file starts: the clock, and the phase.
    private func beginClock() {
        startedAt = Date()
        elapsed = 0
        phase = .recording
        armedReason = nil
    }

    private func beginWriting() {
        runner?.sendReturn()
        beginClock()
    }

    // MARK: Stop

    private func stop() {
        guard let runner, phase == .recording || phase == .armed else { return }
        phase = .stopping
        runner.stop()
    }

    private func finished(status: Int32, asked: Bool) {
        defer {
            let waiting = afterExit
            afterExit = nil
            waiting?()
        }
        ticker?.cancel()
        hub.release(for: id)
        diskSecondsLeft = nil
        meters = []
        runner = nil
        armedReason = nil
        let startedWriting = startedAt != nil
        if asked && (!startedWriting || outputFile == nil) {
            // Cancelled before anything was written: back to the configuration, and the empty file jack_capture
            // created (a header, a few kilobytes) goes.
            if let url = recordedURL, let size = fileSize(url), size <= 8192 { try? FileManager.default.removeItem(at: url) }
            phase = .configuration
            view = .recording
            outputFile = nil
        } else if !asked && outputFile == nil {
            // It stopped without ever naming a file: it did not start.
            errorMessage = warnings.last ?? String(localized: "jack_capture s'est arrêté (code \(status)).")
            phase = .configuration
            view = .recording
        } else {
            phase = .done
            if jackLost && !asked {
                warnings.insert(String(localized: "Le serveur JACK s'est arrêté pendant l'enregistrement. Le fichier contient ce qui a été enregistré jusque-là."), at: 0)
            }
            bytesWritten = totalSize()
            if !asked && status != 0 { warnings.append(String(localized: "jack_capture s'est arrêté de lui-même (code \(status)).")) }
            summary = makeSummary()
            measurePeaks()
        }
    }

    private func makeSummary() -> RecordingSummary? {
        guard let launched, let url = recordedURL else { return nil }
        var summary = RecordingSummary(
            settings: launched.settings, commandText: launched.commandText, sampleRate: launched.sampleRate,
            startedAt: startedAt ?? launched.date, endedAt: Date(), file: url, bytes: bytesWritten,
            xruns: status?.xruns ?? 0, overruns: status?.overruns ?? 0, warnings: warnings,
            fileInfo: SoundFileInfo.read(url))
        let parts = recordedFiles
        if parts.count > 1 {
            summary.partCount = parts.count
            summary.totalDuration = parts.compactMap { SoundFileInfo.read($0)?.duration }.reduce(0, +)
        }
        return summary
    }

    /// Reads the whole file to find the peak of each channel: away from the main actor, the file may be long.
    private func measurePeaks() {
        guard let url = summary?.file else { return }
        let urls = recordedFiles
        summary?.isMeasuringPeaks = true
        Task { [weak self] in
            let peaks = await Task.detached(priority: .utility) { () -> [Float]? in
                // The highest sample of each channel over all the parts.
                var highest: [Float]?
                for part in urls {
                    guard let p = SoundFileInfo.peaks(of: part) else { continue }
                    highest = highest.map { zip($0, p).map(max) } ?? p
                }
                return highest
            }.value
            guard let self, self.summary?.file == url else { return }
            self.summary?.peaks = peaks
            self.summary?.isMeasuringPeaks = false
        }
    }

    // MARK: What jack_capture says

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .recording(let file):
            outputFile = file
        case .waitingToStart(let file):
            outputFile = file
        case .status(let s):
            status = s
        case .meters(let levels):
            guard settings.metersEnabled else { break }
            // The meter of jack_capture shows the highest sample since its last redraw: fall off between two.
            meters = meters.following(levels)
        case .waitingForJack, .flushing, .finished:
            break
        case .message(let text) where text.contains("JACK shutdown"):
            jackLost = true
        case .message(let text):
            if !warnings.contains(text) { warnings.append(text); warnings = Array(warnings.suffix(5)) }
        }
    }

    // MARK: Clock and size

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if self.phase == .recording, let t0 = self.startedAt { self.elapsed = Date().timeIntervalSince(t0) }
                n += 1
                if n % 3 == 0 { self.pollFile() }
                if n % 10 == 0 { self.watchDisk() }
            }
        }
    }

    private func pollFile() {
        guard let url = recordedURL, let size = fileSize(url) else { return }
        if initialSize == nil, phase == .armed { initialSize = size }   // the header, before anything is written
        bytesWritten = rotates ? totalSize() : size
        // Waiting for the transport: the file starts to grow when it rolls.
        if phase == .armed, case .jack? = armedReason, size > (initialSize ?? 0) + 2048 { beginClock() }
    }

    /// Looks at the room left once a second while the file is written: says when little time is left, and stops the recording (its file closed properly) when the
    /// disk gets to the reserve. Several recordings on one disk are stopped together: the room left is the same for all.
    func watchDisk() {
        guard phase == .recording, let run = launched?.settings, let free = freeBytes?() ?? RecordingEstimate.availableBytes(at: run.folderURL) else {
            if phase != .recording { diskSecondsLeft = nil }
            return
        }
        let reserve = DiskGuard.reserveBytes(gigabytes: run.diskReserveGigabytes)
        let rate = RecordingEstimate.bytesPerSecond(run, sampleRate: launched?.sampleRate ?? sampleRate)
        diskSecondsLeft = DiskGuard.secondsLeft(free: free, reserve: reserve, bytesPerSecond: rate)
        switch DiskGuard.verdict(free: free, reserve: reserve, bytesPerSecond: rate) {
        case .fine: break
        case .low:
            guard !lowDiskWarned else { return }
            lowDiskWarned = true
            let minutes = max(1, Int(((diskSecondsLeft ?? 0) / 60).rounded(.up)))
            let text = String(localized: "Il reste de la place pour environ \(minutes) min d'enregistrement.")
            warnings.append(text)
            notify?(String(localized: "Disque presque plein"), text)
        case .stop:
            let text = String(localized: "Le disque est arrivé à sa réserve de \(run.diskReserveGigabytes) Go : l'enregistrement a été arrêté et le fichier refermé.")
            warnings.append(text)
            notify?(String(localized: "Enregistrement arrêté : disque presque plein"), text)
            stop()
        }
    }

    private func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
    }

    private func resetReport() {
        meters = []
        summary = nil
        outputFile = nil
        status = nil
        bytesWritten = 0
        warnings = []
        jackLost = false
        lowDiskWarned = false
        diskSecondsLeft = nil
        elapsed = 0
        startedAt = nil
        initialSize = nil
        armedReason = nil
    }

#if DEBUG
    /// Development aid: put the window in a given state (idle, recording, done) without any recording, to check the interface.
    public func preview(_ state: String) async {
        switch state {
        case "idle": view = .recording
        case "recording":
            view = .recording; phase = .recording; elapsed = 83.4; outputFile = "Prise_04.wav"; bytesWritten = 24_000_000
            status = CaptureStatus(bufferFree: 3.98, bufferTotal: 4.01, diskThreadHighPriority: false, overruns: 0, xruns: 0)
            meters = [ChannelMeter(level: 0.78, peak: 0.86, clipped: false), ChannelMeter(level: 0.55, peak: 0.7, clipped: false)]
        case "done":
            view = .recording; phase = .done; elapsed = 83.4; outputFile = "Prise_04.wav"; bytesWritten = 24_000_000
            summary = RecordingSummary(settings: settings, commandText: command.displayText, sampleRate: sampleRate,
                                       startedAt: Date().addingTimeInterval(-83.4), endedAt: Date(), file: recordedURL ?? settings.folderURL,
                                       bytes: 24_000_000, xruns: 0, overruns: 0, warnings: [], fileInfo: nil)
        default: break
        }
    }
#endif
}
