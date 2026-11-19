// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum IPVersion: String, Codable, Equatable, Sendable, CaseIterable {
    case automatic, ipv4, ipv6
}

/// The sample format `zita-j2n` puts on the network.
public enum SampleFormat: String, Codable, Equatable, Sendable, CaseIterable {
    case bits16, bits24, float32
}

/// Why a set of settings cannot be run. The limits are those of the programs.
public enum SettingsIssue: Equatable, Sendable {
    case emptyAddress
    case portOutOfRange
    case channelsOutOfRange
    case bufferOutOfRange
    case filterOutOfRange
    case packetSizeOutOfRange
    case multicastNeedsInterface
    case emptyClientName
}

/// A list of channels in the form the programs read: strictly ascending numbers, from 1 to 64, with ranges ("1-3,5").
public enum ChannelList {
    public static let maximum = 64

    /// [1, 2, 3, 5] gives "1-3,5". A run of two stays "1,2", as one would write it.
    public static func format(_ channels: [Int]) -> String {
        let sorted = Array(Set(channels)).sorted()
        var parts = [String](), i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
            if j - i >= 2 { parts.append("\(sorted[i])-\(sorted[j])") }
            else { for k in i...j { parts.append("\(sorted[k])") } }
            i = j + 1
        }
        return parts.joined(separator: ",")
    }

    /// The channels of a list, or nil when the programs would refuse it (not ascending, out of 1...64, bad syntax).
    public static func parse(_ text: String) -> [Int]? {
        // Numbers separated by "," or "-" (a range runs up to the next number).
        var number = "", separators = [Character](), numbers = [Int]()
        for c in text where c != " " && c != "\t" {
            if c.isASCII, c.isNumber { number.append(c) }
            else if c == "," || c == "-" {
                guard let n = Int(number) else { return nil }
                numbers.append(n); separators.append(c); number = ""
            } else { return nil }
        }
        guard let last = Int(number) else { return nil }
        numbers.append(last)
        var result = [Int](), previous = 0
        for (index, n) in numbers.enumerated() {
            guard n > previous, n <= maximum else { return nil }
            let rangeFromPrevious = index > 0 && separators[index - 1] == "-"
            if rangeFromPrevious { result.append(contentsOf: (previous + 1)...n) } else { result.append(n) }
            previous = n
        }
        return result
    }
}

/// What the sender (`zita-j2n`) needs.
public struct SendSettings: Equatable, Codable, Sendable {
    /// The address of the receiver, or its name.
    public var address = ""
    public var port = 9999
    /// The number of channels, from 1 to 64: JACK inputs `in_1` … `in_N`.
    public var channels = 2
    public var format = SampleFormat.bits24
    /// The largest packet, in bytes.
    public var packetSize = 1500
    public var multicast = false
    /// The network interface to send multicast on ("en7"). Required for multicast.
    public var interface = ""
    /// How many routers a multicast packet may cross; 1 keeps it on the local network.
    public var hops = 1
    public var ipVersion = IPVersion.automatic
    public var clientName = "zita-j2n"

    public init() {}

    public var issues: [SettingsIssue] {
        var found = [SettingsIssue]()
        if address.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyAddress) }
        if !(1...65535).contains(port) { found.append(.portOutOfRange) }
        if !(1...ChannelList.maximum).contains(channels) { found.append(.channelsOutOfRange) }
        if !(576...9216).contains(packetSize) { found.append(.packetSizeOutOfRange) }
        if multicast, interface.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.multicastNeedsInterface) }
        if clientName.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyClientName) }
        return found
    }
}

/// What the receiver (`zita-n2j`) needs.
public struct ReceiveSettings: Equatable, Codable, Sendable {
    /// An address of this Mac to listen on (the one the sender is given), or the address of a multicast group.
    public var address = ""
    public var port = 9999
    /// The channels to receive, from 1 to 64: JACK outputs `out_N`, named after the channel number. A channel the sender does
    /// not send stays silent. The ports exist from the start, before any sender is there, so they can be wired at once.
    public var channels = [1, 2]
    /// Extra buffering, in milliseconds, from 0 to 4000.
    public var bufferMilliseconds = 10
    /// The length of the resampler filter, 16 to 96; nil lets the program choose.
    public var filterDelay: Int?
    public var multicast = false
    public var interface = ""
    public var ipVersion = IPVersion.automatic
    public var clientName = "zita-n2j"

    public init() {}

    public var issues: [SettingsIssue] {
        var found = [SettingsIssue]()
        if address.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyAddress) }
        if !(1...65535).contains(port) { found.append(.portOutOfRange) }
        if channels.isEmpty || Set(channels).count != channels.count || channels.contains(where: { !(1...ChannelList.maximum).contains($0) }) {
            found.append(.channelsOutOfRange)
        }
        if !(0...4000).contains(bufferMilliseconds) { found.append(.bufferOutOfRange) }
        if let delay = filterDelay, !(16...96).contains(delay) { found.append(.filterOutOfRange) }
        if multicast, interface.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.multicastNeedsInterface) }
        if clientName.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyClientName) }
        return found
    }
}
