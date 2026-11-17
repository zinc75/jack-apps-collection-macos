// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// The playlist and what it does to the player: which file is open, which one comes next (the player makes its program in
/// advance, so that the files follow each other without a gap), and what happens when a file ends. The playlist plays in the
/// mode where the application drives the program; it has no say when the JACK transport does.
@MainActor
@Observable
public final class PlaylistModel {
    public private(set) var playlist = Playlist()
    public let player: PlayerModel
    /// Said after every change of the list, of the current file or of the repeat mode: the application keeps them.
    @ObservationIgnored public var onChange: (() -> Void)?
    /// Whether a file can be played now; replaced in tests.
    @ObservationIgnored public var isPlayable: (URL) -> Bool = { FileManager.default.isReadableFile(atPath: $0.path) }

    public init(player: PlayerModel) {
        self.player = player
        player.onFileEnded = { [weak self] in self?.fileEnded() }
    }

    public var repeatMode: RepeatMode { playlist.repeatMode }
    public var hasNext: Bool { nextPlayableIndex() != nil }
    public var hasPrevious: Bool { previousPlayableIndex() != nil }
    /// The file the list goes on with, for the line "next".
    public var nextFile: URL? { nextPlayableIndex().map { playlist.items[$0] } }

    // MARK: Changing the list

    /// The files of the list, with the place of the current one: from the settings kept at the last launch. The file is opened
    /// and waits, paused.
    public func restore(items: [URL], current: Int?, repeatMode: RepeatMode) {
        playlist = Playlist(items: items, current: nil, repeatMode: repeatMode)
        applyRepeat()
        if let current, items.indices.contains(current) {
            playlist.current = current
            player.open(items[current])
        }
        sync()
    }

    /// A new list, which replaces the old one: the first file is open (and plays, if asked).
    public func replace(with urls: [URL], play: Bool = false) {
        playlist.removeAll()
        playlist.append(urls)
        applyRepeat()
        guard !urls.isEmpty else { player.closeFile(); sync(); return }
        select(0, play: play)
    }

    public func append(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let wasEmpty = playlist.isEmpty
        playlist.append(urls)
        applyRepeat()
        if wasEmpty { select(0, play: false) } else { sync() }
    }

    public func insert(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty else { return }
        let wasEmpty = playlist.isEmpty
        playlist.insert(urls, at: index)
        applyRepeat()
        if wasEmpty { select(0, play: false) } else { sync() }
    }

    public func remove(at offsets: IndexSet) {
        let hadCurrent = playlist.current != nil
        playlist.remove(at: offsets)
        applyRepeat()
        // The file that plays is not taken out of the player: it plays to its end, and the list then goes on from where it was.
        if hadCurrent, playlist.current == nil, playlist.isEmpty { player.closeFile() }
        sync()
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        playlist.move(from: offsets, to: destination)
        sync()
    }

    public func setRepeat(_ mode: RepeatMode) {
        playlist.repeatMode = mode
        applyRepeat()
        sync()
    }

    // MARK: Moving in the list

    /// Opens the file at this place of the list.
    public func select(_ index: Int, play: Bool) {
        guard playlist.items.indices.contains(index) else { return }
        playlist.current = index
        syncNumbers()      // the program of this file is named for its place from the start
        player.open(playlist.items[index], play: play)
        sync()
    }

    /// The next file, now: the one that is ready takes over at once, else it is opened.
    public func next() {
        guard let n = nextPlayableIndex() else { return }
        go(to: n, play: player.isPlaying)
    }

    /// The file before: from its beginning when the current one has gone on for more than 3 seconds.
    public func previous() {
        if player.positionSeconds > 3 || previousPlayableIndex() == nil { player.seek(fraction: 0); return }
        if let p = previousPlayableIndex() { go(to: p, play: player.isPlaying) }
    }

    // MARK: The end of a file

    private func fileEnded() {
        guard player.mode == .independent, !playlist.loopsTheFile, let n = nextPlayableIndex() else { return }
        go(to: n, play: true)
    }

    /// Goes to a file of the list: the program made in advance takes over when it is the right one, else the file is opened.
    private func go(to index: Int, play: Bool) {
        let url = playlist.items[index]
        if player.nextFile == url, player.advanceToNext(play: play) {
            playlist.current = index
            sync()
        } else {
            select(index, play: play)
        }
    }

    // MARK: What the player is told

    private func nextPlayableIndex() -> Int? {
        var p = playlist
        for _ in 0..<max(p.count, 1) {
            guard let n = p.nextIndex else { return nil }
            if isPlayable(p.items[n]) { return n }
            p.current = n
        }
        return nil
    }

    private func previousPlayableIndex() -> Int? {
        var p = playlist
        for _ in 0..<max(p.count, 1) {
            guard let n = p.previousIndex else { return nil }
            if isPlayable(p.items[n]) { return n }
            p.current = n
        }
        return nil
    }

    /// The program loops the file by itself in the `file` mode, and for the one file of a list that repeats.
    private func applyRepeat() {
        var s = player.settings
        guard s.loop != playlist.loopsTheFile else { return }
        s.loop = playlist.loopsTheFile
        player.update(settings: s)
    }

    private func syncNumbers() {
        let many = playlist.count > 1
        player.listCount = many ? playlist.count : nil
        player.currentNumber = many ? playlist.current.map { $0 + 1 } : nil
    }

    /// Tells the player the size of the list, the place of the file that plays and the file that comes next (its program is
    /// made in advance, and named for its place), then the application, which keeps the list.
    private func sync() {
        syncNumbers()
        let next = playlist.loopsTheFile ? nil : nextPlayableIndex()
        player.nextNumber = next.map { $0 + 1 }
        player.nextFile = next.map { playlist.items[$0] }
        onChange?()
    }
}
