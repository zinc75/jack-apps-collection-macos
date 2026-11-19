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
    /// Neither an address nor a name (see `AddressCheck`).
    case invalidAddress
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

/// Multicast sends to a group: one address that every receiver listens to, instead of the address of each receiver.
public enum MulticastAddress {
    /// Whether an address is one of a multicast group: 224.0.0.0 to 239.255.255.255 for IPv4, ff00::/8 for IPv6. A name is not judged
    /// (it may resolve to a group).
    public static func isGroup(_ text: String) -> Bool {
        let address = text.trimmingCharacters(in: .whitespaces)
        if address.contains(":") { return address.lowercased().hasPrefix("ff") }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, let first = Int(parts[0]), parts.dropFirst().allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return false }
        return (224...239).contains(first)
    }

    /// Whether an address or a name designates a multicast group, as the programs decide: after resolving it, and by the first result they
    /// take. A numeric address is judged at once; a name is resolved off the calling thread (it may take a moment). Nil when the name does
    /// not resolve, or is empty.
    public static func isGroupResolving(_ host: String) async -> Bool? {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if isNumeric(name) { return isGroup(name) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_DGRAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { continuation.resume(returning: nil); return }
                defer { freeaddrinfo(result) }
                guard let address = first.pointee.ai_addr else { continuation.resume(returning: nil); return }
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    continuation.resume(returning: value & 0xF000_0000 == 0xE000_0000)
                case AF_INET6:
                    let first = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 }
                    continuation.resume(returning: first == 0xFF)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Whether the text looks like a numeric address (not a name), so that a wrong one can be said.
    public static func isNumeric(_ text: String) -> Bool {
        let address = text.trimmingCharacters(in: .whitespaces)
        if address.contains(":") { return true }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
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
        switch AddressCheck.syntax(of: address) {
        case .empty: found.append(.emptyAddress)
        case .invalid: found.append(.invalidAddress)
        default: break
        }
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
    /// Receive every channel the sender sends (the default). The program has to be told the channels when it starts, and the
    /// sender's number is only known once it is heard: so the program starts with the number the sender had last time, and is
    /// started again, once, when the sender turns out to have another.
    public var automaticChannels = true
    /// How many channels the sender sent when it was last heard (2 the first time): what an automatic receiver starts with.
    public var knownSenderChannels = 2
    /// The channels to receive when they are chosen, from 1 to 64: JACK outputs `out_N`, named after the channel number. A channel
    /// the sender does not send stays silent. The ports exist from the start, before any sender is there, so they can be wired at once.
    public var channels = [1, 2]
    /// The channels the program is started with: all of the sender's, or the chosen ones.
    public var effectiveChannels: [Int] {
        automaticChannels ? Array(1...min(max(knownSenderChannels, 1), ChannelList.maximum)) : channels
    }
    /// Extra buffering, in milliseconds, from 0 to 4000.
    public var bufferMilliseconds = 10
    /// The length of the resampler filter, 16 to 96; nil lets the program choose.
    public var filterDelay: Int?
    public var multicast = false
    public var interface = ""
    public var ipVersion = IPVersion.automatic
    public var clientName = "zita-n2j"

    public init() {}

    // Settings saved by an earlier version have no key for what was added since: each one has its default.
    private enum CodingKeys: String, CodingKey {
        case address, port, automaticChannels, knownSenderChannels, channels, bufferMilliseconds, filterDelay, multicast, interface, ipVersion, clientName
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReceiveSettings()
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? d.address
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? d.port
        automaticChannels = try c.decodeIfPresent(Bool.self, forKey: .automaticChannels) ?? d.automaticChannels
        knownSenderChannels = try c.decodeIfPresent(Int.self, forKey: .knownSenderChannels) ?? d.knownSenderChannels
        channels = try c.decodeIfPresent([Int].self, forKey: .channels) ?? d.channels
        bufferMilliseconds = try c.decodeIfPresent(Int.self, forKey: .bufferMilliseconds) ?? d.bufferMilliseconds
        filterDelay = try c.decodeIfPresent(Int.self, forKey: .filterDelay)
        multicast = try c.decodeIfPresent(Bool.self, forKey: .multicast) ?? d.multicast
        interface = try c.decodeIfPresent(String.self, forKey: .interface) ?? d.interface
        ipVersion = try c.decodeIfPresent(IPVersion.self, forKey: .ipVersion) ?? d.ipVersion
        clientName = try c.decodeIfPresent(String.self, forKey: .clientName) ?? d.clientName
    }

    public var issues: [SettingsIssue] {
        var found = [SettingsIssue]()
        switch AddressCheck.syntax(of: address) {
        case .empty: found.append(.emptyAddress)
        case .invalid: found.append(.invalidAddress)
        default: break
        }
        if !(1...65535).contains(port) { found.append(.portOutOfRange) }
        let list = effectiveChannels
        if list.isEmpty || Set(list).count != list.count || list.contains(where: { !(1...ChannelList.maximum).contains($0) }) {
            found.append(.channelsOutOfRange)
        }
        if !(0...4000).contains(bufferMilliseconds) { found.append(.bufferOutOfRange) }
        if let delay = filterDelay, !(16...96).contains(delay) { found.append(.filterOutOfRange) }
        if multicast, interface.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.multicastNeedsInterface) }
        if clientName.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyClientName) }
        return found
    }
}
