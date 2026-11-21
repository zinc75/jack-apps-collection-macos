// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SoundFileKit

/// The sound files of a configuration, looked at once: what libsndfile says about each is kept as long as the file does
/// not change (its date and its size), so that the matrix can ask as often as it likes.
public final class SoundFileCatalog: @unchecked Sendable {
    private struct Stamp: Equatable { var date: Date?; var size: Int? }
    private struct Entry { var stamp: Stamp; var info: SoundFileInfo?; var analysis: [ImpulseAnalysis]? }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    private func stamp(of path: String) -> Stamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return Stamp(date: attributes?[.modificationDate] as? Date, size: (attributes?[.size] as? NSNumber)?.intValue)
    }

    /// What is known of a file; nil when it is not there or is not a sound file.
    public func info(at path: String) -> SoundFileInfo? {
        let current = stamp(of: path)
        lock.lock()
        if let entry = entries[path], entry.stamp == current { lock.unlock(); return entry.info }
        lock.unlock()
        let info = try? SoundFile.probe(URL(fileURLWithPath: path))
        lock.lock()
        entries[path] = Entry(stamp: current, info: info, analysis: nil)
        lock.unlock()
        return info
    }

    /// The analysis of every channel of an impulse response file (reads the whole file the first time).
    public func analysis(at path: String) -> [ImpulseAnalysis]? {
        let current = stamp(of: path)
        lock.lock()
        if let entry = entries[path], entry.stamp == current, let analysis = entry.analysis { lock.unlock(); return analysis }
        lock.unlock()
        guard let file = try? SoundFile(url: URL(fileURLWithPath: path)), let analysis = try? file.analyzeImpulses() else { return nil }
        lock.lock()
        entries[path] = Entry(stamp: current, info: file.info, analysis: analysis)
        lock.unlock()
        return analysis
    }

    /// Forgets what it knows: one file, or all of them.
    public func forget(_ path: String? = nil) {
        lock.lock()
        if let path { entries[path] = nil } else { entries.removeAll() }
        lock.unlock()
    }
}
