// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JackPlayKit
import Observation
import UniformTypeIdentifiers

/// The pages of the window: the playing first, then the sections of the settings.
enum Page: String, CaseIterable, Identifiable {
    case play, outputs, loop, advanced, display
    var id: String { rawValue }
}

/// What the window needs besides the player: the page shown, the settings kept between launches, opening a file.
@MainActor
@Observable
final class AppModel {
    var page: Page = .play
    let graph = PlaybackGraph()
    let player: PlayerModel
    private let defaults: UserDefaults?
    /// A move on the waveform that is waiting to be sent: scrubbing sends at most one every 30 ms.
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var seekTask: Task<Void, Never>?

    private enum Key {
        static let converter = "converter", buffer = "bufferFrames", name = "clientName", loop = "loop"
        static let mode = "mode", autoConnect = "autoConnect", commandsTransport = "commandsTransport", lastFolder = "lastFolder"
    }

    /// - Parameter defaults: where the settings are kept; nil for a run that must not keep them.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let d = defaults ?? UserDefaults(suiteName: "jackplay.volatile.\(UUID().uuidString)")!
        var settings = PlayerSettings()
        if d.object(forKey: Key.converter) != nil { settings.converter = d.integer(forKey: Key.converter) }
        if d.object(forKey: Key.buffer) != nil, PlayerSettings.bufferSizes.contains(d.integer(forKey: Key.buffer)) { settings.bufferFrames = d.integer(forKey: Key.buffer) }
        if let name = d.string(forKey: Key.name) { settings.clientName = name }
        settings.loop = d.bool(forKey: Key.loop)
        let mode: PlayerCommand.Mode = d.string(forKey: Key.mode) == "follow" ? .followTransport : .independent
        let graph = self.graph
        let player = PlayerModel(server: graph, store: ConnectionStore(defaults: defaults ?? d), settings: settings, mode: mode) { command in
            guard let executable = PlayerHelper.executableURL() else { return nil }
            return PlayerProcess(executable: executable, command: command)
        }
        if d.object(forKey: Key.autoConnect) != nil { player.autoConnect = d.bool(forKey: Key.autoConnect) }
        if d.object(forKey: Key.commandsTransport) != nil { player.commandsTransport = d.bool(forKey: Key.commandsTransport) }
        self.player = player
    }

    func start() { graph.start() }

    // MARK: Files

    static let audioTypes: [UTType] = {
        var types: [UTType] = [.audio]
        for ext in ["wav", "wave", "aif", "aiff", "caf", "flac", "ogg", "oga", "opus", "mp3", "w64", "rf64", "au"] {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types
    }()

    /// The panel to choose a file: any file is accepted, libsndfile says whether it can read it.
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.audioTypes
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisir un fichier audio")
        if let folder = defaults?.string(forKey: Key.lastFolder) { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        defaults?.set(url.deletingLastPathComponent().path, forKey: Key.lastFolder)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        player.open(url)
        page = .play
    }

    // MARK: Moving on the waveform

    /// A move while the pointer drags on the waveform: sent at once the first time, then at most every 30 ms, and the last one always.
    func scrub(to fraction: Double) {
        pendingSeek = fraction
        guard seekTask == nil else { return }
        flushSeek()
        seekTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard let self else { return }
                if self.pendingSeek == nil { self.seekTask = nil; return }
                self.flushSeek()
            }
        }
    }

    private func flushSeek() {
        guard let f = pendingSeek else { return }
        pendingSeek = nil
        player.seek(fraction: f)
    }

    // MARK: Settings, kept as they change

    func set(loop: Bool) {
        var s = player.settings
        s.loop = loop
        player.update(settings: s)
        defaults?.set(loop, forKey: Key.loop)
    }

    func set(converter: Int) {
        var s = player.settings
        s.converter = converter
        player.update(settings: s)
        defaults?.set(converter, forKey: Key.converter)
    }

    func set(bufferFrames: Int) {
        var s = player.settings
        s.bufferFrames = bufferFrames
        player.update(settings: s)
        defaults?.set(bufferFrames, forKey: Key.buffer)
    }

    func set(clientName: String) {
        var s = player.settings
        s.clientName = clientName
        player.update(settings: s)
        defaults?.set(clientName, forKey: Key.name)
    }

    func set(mode: PlayerCommand.Mode) {
        player.set(mode: mode)
        defaults?.set(mode == .followTransport ? "follow" : "independent", forKey: Key.mode)
    }

    func set(autoConnect: Bool) {
        player.autoConnect = autoConnect
        defaults?.set(autoConnect, forKey: Key.autoConnect)
    }

    func set(commandsTransport: Bool) {
        player.commandsTransport = commandsTransport
        defaults?.set(commandsTransport, forKey: Key.commandsTransport)
    }

    /// The program does not outlive the application.
    func shutdown() { player.closeFile() }
}
