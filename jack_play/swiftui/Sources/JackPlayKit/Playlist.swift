// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What happens when the file that plays has ended.
public enum RepeatMode: String, Equatable, Sendable, CaseIterable {
    /// The list plays once, and the last file stays paused at its end.
    case off
    /// The list starts again after its last file.
    case list
    /// The file that plays starts again and again (`-l` of the program).
    case file
}

/// An ordered list of files and the place of the one that plays. A value: the rules of the order are here, the playing is in
/// `PlaylistModel`.
public struct Playlist: Equatable, Sendable {
    public var items: [URL]
    /// The place of the file that is open, or nil when there is none.
    public var current: Int?
    public var repeatMode: RepeatMode

    public init(items: [URL] = [], current: Int? = nil, repeatMode: RepeatMode = .off) {
        self.items = items
        self.current = current.flatMap { items.indices.contains($0) ? $0 : nil }
        self.repeatMode = repeatMode
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// The place of the file that follows the current one, or nil when the list ends there. A list of one file that repeats
    /// plays the same file again: that is the `file` mode, never a second program of the same name.
    public var nextIndex: Int? {
        guard let current else { return items.isEmpty ? nil : 0 }
        if repeatMode == .file { return nil }
        if current + 1 < items.count { return current + 1 }
        return repeatMode == .list && items.count > 1 ? 0 : nil
    }

    /// The place of the file before the current one: the last one when the list repeats and this is the first.
    public var previousIndex: Int? {
        guard let current else { return nil }
        if current > 0 { return current - 1 }
        return repeatMode == .list && items.count > 1 ? items.count - 1 : nil
    }

    /// Whether the program has to loop the file itself (`-l`): the one file of a list that repeats, or the `file` mode.
    public var loopsTheFile: Bool { repeatMode == .file || (repeatMode == .list && items.count == 1) }

    // MARK: Changes

    public mutating func append(_ urls: [URL]) {
        items += urls
    }

    public mutating func insert(_ urls: [URL], at index: Int) {
        let at = min(max(index, 0), items.count)
        items.insert(contentsOf: urls, at: at)
        if let c = current, at <= c { current = c + urls.count }
    }

    /// Takes the files at these places out. The current one may be one of them: the list then has no current file.
    public mutating func remove(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        if let c = current {
            current = offsets.contains(c) ? nil : c - offsets.filter { $0 < c }.count
        }
        items = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Moves the files at these places to a place of the list (the same convention as `Array.move(fromOffsets:toOffset:)`).
    public mutating func move(from offsets: IndexSet, to destination: Int) {
        // Each file carries its old place, so that the current one is followed (the same file may be twice in the list).
        var entries = Array(items.enumerated())
        let taken = offsets.sorted().map { entries[$0] }
        let before = offsets.filter { $0 < destination }.count
        for o in offsets.sorted(by: >) { entries.remove(at: o) }
        entries.insert(contentsOf: taken, at: min(max(destination - before, 0), entries.count))
        current = current.flatMap { c in entries.firstIndex { $0.offset == c } }
        items = entries.map(\.element)
    }

    public mutating func removeAll() {
        items = []
        current = nil
    }
}

// MARK: - M3U8

/// The playlist file the application opens and writes: M3U8, one path per line, UTF-8, `#` for comments. Any player reads it.
public enum M3U {
    public static let fileExtensions = ["m3u8", "m3u"]

    /// The files a playlist file names. A relative path is taken from the folder of the playlist, `file://` addresses work too.
    /// Blank lines and comments (`#EXTM3U`, `#EXTINF`, ...) are ignored.
    public static func parse(_ text: String, folder: URL) -> [URL] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if line.hasPrefix("file://"), let url = URL(string: line) { return url.standardizedFileURL }
            if line.hasPrefix("/") { return URL(fileURLWithPath: line).standardizedFileURL }
            return URL(fileURLWithPath: line, relativeTo: folder).standardizedFileURL
        }
    }

    /// The text of a playlist file. A file inside the folder of the playlist is written with a relative path, so that the folder
    /// can be moved with its list; the others are absolute.
    public static func text(for urls: [URL], folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let lines = urls.map { url -> String in
            let path = url.standardizedFileURL.path
            return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
        }
        return (["#EXTM3U"] + lines).joined(separator: "\n") + "\n"
    }
}
