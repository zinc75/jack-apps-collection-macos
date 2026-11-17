// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JackPlayKit
import Observation
import UniformTypeIdentifiers

/// The pages of the window: the playing first, then the sections of the settings.
enum Page: String, CaseIterable, Identifiable {
    case play, playlist, outputs, loop, advanced, display
    var id: String { rawValue }
}

/// What the window needs besides the player: the page shown, the settings kept between launches, opening a file.
@MainActor
@Observable
final class AppModel {
    var page: Page = .play
    let graph = PlaybackGraph()
    let player: PlayerModel
    let playlist: PlaylistModel
    private let defaults: UserDefaults?
    /// A move on the waveform that is waiting to be sent: scrubbing sends at most one every 30 ms.
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var seekTask: Task<Void, Never>?

    private enum Key {
        static let converter = "converter", buffer = "bufferFrames", name = "clientName", loop = "loop"
        static let list = "playlist", listCurrent = "playlistCurrent", repeatMode = "repeatMode"
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
        let playlist = PlaylistModel(player: player)
        self.playlist = playlist
        // The list and the place in it come back as they were left: the file waits, paused, as if it had just been opened.
        let repeatMode = d.string(forKey: Key.repeatMode).flatMap(RepeatMode.init(rawValue:)) ?? (settings.loop ? .file : .off)
        var items = (d.stringArray(forKey: Key.list) ?? []).map { URL(fileURLWithPath: $0) }
        var current: Int? = d.object(forKey: Key.listCurrent) == nil ? nil : d.integer(forKey: Key.listCurrent)
        if let c = current, !(items.indices.contains(c) && FileManager.default.isReadableFile(atPath: items[c].path)) { current = nil }
        if defaults == nil { items = [] }
        playlist.restore(items: items, current: current, repeatMode: repeatMode)
        playlist.onChange = { [weak self] in self?.saveList() }
    }

    private func saveList() {
        guard let defaults else { return }
        defaults.set(playlist.playlist.items.map(\.path), forKey: Key.list)
        defaults.set(playlist.playlist.current, forKey: Key.listCurrent)
        defaults.set(playlist.repeatMode.rawValue, forKey: Key.repeatMode)
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

    /// The panel to choose files: any file is accepted, libsndfile says whether it can read it. A playlist file is read too.
    private func choosePanel(message: String, multiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.audioTypes + Self.playlistTypes
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        panel.message = message
        if let folder = defaults?.string(forKey: Key.lastFolder) { panel.directoryURL = URL(fileURLWithPath: folder) }
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// "Open": the files chosen are the new list.
    func chooseFile() {
        let urls = choosePanel(message: String(localized: "Choisir des fichiers audio"))
        if !urls.isEmpty { open(urls) }
    }

    /// "Add": the files chosen go at the end of the list.
    func addFiles() {
        let urls = choosePanel(message: String(localized: "Ajouter des fichiers à la liste"))
        if !urls.isEmpty { add(urls) }
    }

    static let playlistTypes: [UTType] = M3U.fileExtensions.compactMap { UTType(filenameExtension: $0) }

    /// The audio files behind what was chosen, dropped or opened: a playlist file is replaced by the files it lists.
    private func audioFiles(in urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard M3U.fileExtensions.contains(url.pathExtension.lowercased()) else { return [url] }
            guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else { return [] }
            return M3U.parse(text, folder: url.deletingLastPathComponent())
        }
    }

    func open(_ url: URL) { open([url]) }

    /// These files are the new list, and the first one is open.
    func open(_ urls: [URL]) {
        let files = audioFiles(in: urls)
        guard let first = files.first else { return }
        remember(first)
        playlist.replace(with: files)
        page = files.count > 1 ? .playlist : .play
    }

    /// Files dropped on the window or on the list: opened as the new list, or added to the end of it.
    func receive(_ providers: [NSItemProvider], append: Bool) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        var urls = [URL?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async { urls[i] = url; group.leave() }
            }
        }
        group.notify(queue: .main) { [weak self] in
            let found = urls.compactMap { $0 }
            guard !found.isEmpty else { return }
            if append { self?.add(found) } else { self?.open(found) }
        }
        return true
    }

    /// These files go at the end of the list.
    func add(_ urls: [URL]) {
        let files = audioFiles(in: urls)
        guard let first = files.first else { return }
        remember(first)
        playlist.append(files)
    }

    private func remember(_ url: URL) {
        defaults?.set(url.deletingLastPathComponent().path, forKey: Key.lastFolder)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// "Open a list": a playlist file (M3U8 or M3U) replaces the list.
    func openPlaylistFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.playlistTypes
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisir une liste de lecture")
        if let folder = defaults?.string(forKey: Key.lastFolder) { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open([url])
    }

    /// The playlist in a file that other players read too (M3U8).
    func savePlaylist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.playlistTypes.filter { $0.preferredFilenameExtension == "m3u8" }
        panel.nameFieldStringValue = String(localized: "Liste de lecture") + ".m3u8"
        if let folder = defaults?.string(forKey: Key.lastFolder) { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = M3U.text(for: playlist.playlist.items, folder: url.deletingLastPathComponent())
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: What the files are

    @ObservationIgnored private var infos: [URL: SoundFileInfo?] = [:]

    /// What is known about a file of the list (read once).
    func info(of url: URL) -> SoundFileInfo? {
        if let known = infos[url] { return known }
        let info = try? SoundFile.probe(url)
        infos[url] = .some(info)
        return info
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

    func set(repeatMode: RepeatMode) {
        playlist.setRepeat(repeatMode)
    }

    /// The button of the footer: no repeat, then the list, then the file (a list of one file has no "list" step).
    func cycleRepeat() {
        switch playlist.repeatMode {
        case .off: playlist.setRepeat(playlist.playlist.count > 1 ? .list : .file)
        case .list: playlist.setRepeat(.file)
        case .file: playlist.setRepeat(.off)
        }
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
