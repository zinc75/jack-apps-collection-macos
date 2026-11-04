// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Which JACK output feeds which channel of the file. Several sources in a channel are summed by
/// JACK; one output may feed several channels.
public struct SourceAssignment: Equatable, Sendable {
    /// For each channel, the full port names ("client:port") that feed it.
    public private(set) var perChannel: [[String]]

    public init(_ sources: [[String]] = [], channels: Int) {
        perChannel = Array(sources.prefix(channels))
        while perChannel.count < channels { perChannel.append([]) }
    }

    public var channelCount: Int { perChannel.count }

    /// Grows or shrinks the list; the last channels go first.
    public mutating func resize(to channels: Int) {
        let n = max(channels, 1)
        if perChannel.count > n { perChannel.removeLast(perChannel.count - n) }
        while perChannel.count < n { perChannel.append([]) }
    }

    public func isOn(port: String, channel: Int) -> Bool {
        perChannel.indices.contains(channel) && perChannel[channel].contains(port)
    }

    public mutating func toggle(port: String, channel: Int) {
        guard perChannel.indices.contains(channel) else { return }
        if let i = perChannel[channel].firstIndex(of: port) {
            perChannel[channel].remove(at: i)
        } else {
            perChannel[channel].append(port)
        }
    }

    public mutating func clear() {
        for i in perChannel.indices { perChannel[i] = [] }
    }

    /// One source per channel, in order: the first port for channel 1, and so on.
    public mutating func fill(with ports: [String]) {
        for i in perChannel.indices { perChannel[i] = i < ports.count ? [ports[i]] : [] }
    }

    /// Channels with at least one source.
    public var usedCount: Int { perChannel.filter { !$0.isEmpty }.count }
    /// Channels with several sources, which are added together.
    public var summedCount: Int { perChannel.filter { $0.count > 1 }.count }
}
