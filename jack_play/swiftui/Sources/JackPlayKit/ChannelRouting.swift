// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which file it is, for the connections remembered for it. It is the name of the file, its size and its date of
/// modification: moving the file to another folder keeps its connections, and a file that has been changed gets new ones.
public struct FileKey: Codable, Hashable, Sendable {
    public let name: String
    public let size: Int64
    /// Seconds since 1970.
    public let modified: Int64

    public init(name: String, size: Int64, modified: Int64) {
        self.name = name
        self.size = size
        self.modified = modified
    }

    public init(url: URL) {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        self.init(name: url.lastPathComponent,
                  size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                  modified: Int64((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0))
    }

    public var id: String { "\(name)|\(size)|\(modified)" }
}

/// Where each channel of a file goes: for each channel, the JACK input ports it is connected to, as `"client:port"`.
/// A channel can feed several ports, and a port can receive several channels (JACK adds them).
public struct ChannelRouting: Codable, Equatable, Sendable {
    public var channels: [[String]]

    public init(channels: [[String]]) { self.channels = channels }

    public static func empty(channels: Int) -> ChannelRouting {
        ChannelRouting(channels: Array(repeating: [], count: max(channels, 0)))
    }

    /// The same routing for a file with `count` channels: the extra channels are dropped, the missing ones are not connected.
    public func resized(to count: Int) -> ChannelRouting {
        var c = Array(channels.prefix(count))
        while c.count < count { c.append([]) }
        return ChannelRouting(channels: c)
    }

    /// Channels with at least one destination.
    public var connectedChannels: Int { channels.filter { !$0.isEmpty }.count }

    /// Whether a channel goes to a port.
    public func contains(channel: Int, port: String) -> Bool {
        channels.indices.contains(channel) && channels[channel].contains(port)
    }

    /// Connects or disconnects a channel and a port.
    public mutating func toggle(channel: Int, port: String) {
        guard channels.indices.contains(channel) else { return }
        if let i = channels[channel].firstIndex(of: port) { channels[channel].remove(at: i) } else { channels[channel].append(port) }
    }

    /// Ports that receive more than one channel: JACK adds their signals, and nothing says it loudly.
    public var summedPorts: Set<String> {
        var count = [String: Int]()
        for ports in channels { for p in Set(ports) { count[p, default: 0] += 1 } }
        return Set(count.filter { $0.value > 1 }.keys)
    }

    /// Every clients named in the routing, in the order they first appear.
    public var clients: [String] {
        var seen = [String]()
        for ports in channels { for p in ports { if let c = Self.client(of: p), !seen.contains(c) { seen.append(c) } } }
        return seen
    }

    static func client(of port: String) -> String? {
        port.firstIndex(of: ":").map { String(port[..<$0]) }
    }
}

/// What a file gets the first time it is opened: its channels go to the first playback ports of the system, in order. A
/// file with one channel goes to the first two (left and right), as a person expects from a mono sound.
public enum DefaultRouting {
    public static func make(channels: Int, playbackPorts: [String]) -> ChannelRouting {
        if channels == 1 {
            return ChannelRouting(channels: [Array(playbackPorts.prefix(2))])
        }
        return ChannelRouting(channels: (0..<max(channels, 0)).map { playbackPorts.indices.contains($0) ? [playbackPorts[$0]] : [] })
    }
}
