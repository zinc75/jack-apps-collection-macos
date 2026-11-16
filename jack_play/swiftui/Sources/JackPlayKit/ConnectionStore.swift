// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The connections remembered for each file, kept between launches. A file that has not been opened for a long time is
/// forgotten, and so are the oldest ones when there are too many.
public final class ConnectionStore {
    struct Entry: Codable, Equatable {
        var routing: ChannelRouting
        var lastUsed: Date
    }

    public static let defaultsKey = "fileRoutings"
    public static let maxEntries = 500
    public static let maxAge: TimeInterval = 365 * 24 * 3600

    private let defaults: UserDefaults
    private let now: () -> Date
    private var entries: [String: Entry]

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.defaultsKey), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        prune()
    }

    public var count: Int { entries.count }

    /// What is remembered for a file, or nil the first time.
    public func routing(for key: FileKey, channels: Int) -> ChannelRouting? {
        guard var entry = entries[key.id] else { return nil }
        entry.lastUsed = now()
        entries[key.id] = entry
        return entry.routing.resized(to: channels)
    }

    public func remember(_ routing: ChannelRouting, for key: FileKey) {
        entries[key.id] = Entry(routing: routing, lastUsed: now())
        prune()
        save()
    }

    public func forget(_ key: FileKey) {
        entries[key.id] = nil
        save()
    }

    /// Writes what has been read since the last write (the date of last use).
    public func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    private func prune() {
        let limit = now().addingTimeInterval(-Self.maxAge)
        entries = entries.filter { $0.value.lastUsed >= limit }
        if entries.count > Self.maxEntries {
            let keep = entries.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(Self.maxEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
