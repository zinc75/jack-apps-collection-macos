// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge

public enum LinkDirection: String, Codable, Sendable, CaseIterable {
    /// `zita-j2n`: JACK ports of other clients feed its inputs `in_1` … `in_N`, which go onto the network.
    case send
    /// `zita-n2j`: its outputs `out_N` carry what comes from the network, to JACK ports of other clients.
    case receive
}

/// Where each channel of a direction is wired, by channel number (from 1, which is the number in the name of the port of
/// the program: `in_3`, `out_3`): the JACK ports of the other clients. For the sender they are outputs that feed the channel;
/// for the receiver, inputs that the channel feeds. A channel can have several ports, and a port can take several channels
/// of the receiver (JACK adds them).
///
/// The wiring is kept apart from the programs: it is made when a program runs, again each time it starts, and kept while it
/// does not run, so that it can be prepared before the other Mac is there.
public struct ChannelWiring: Codable, Equatable, Sendable {
    public var ports: [Int: [String]]

    public init(ports: [Int: [String]] = [:]) { self.ports = ports }

    public static let empty = ChannelWiring()

    public func contains(channel: Int, port: String) -> Bool { ports[channel]?.contains(port) ?? false }

    /// Wires or unwires a channel and a port.
    public mutating func toggle(channel: Int, port: String) {
        var list = ports[channel] ?? []
        if let i = list.firstIndex(of: port) { list.remove(at: i) } else { list.append(port) }
        ports[channel] = list.isEmpty ? nil : list
    }

    public mutating func clear() { ports = [:] }

    /// The channels, among `channels`, that have no port: the sender sends silence on them, the receiver's output stays unconnected.
    public func unwired(in channels: [Int]) -> [Int] { channels.filter { (ports[$0] ?? []).isEmpty } }

    /// Ports that take more than one of `channels`: JACK adds their signals, and nothing says it loudly.
    public func summedPorts(in channels: [Int]) -> Set<String> {
        var count = [String: Int]()
        for c in channels { for p in Set(ports[c] ?? []) { count[p, default: 0] += 1 } }
        return Set(count.filter { $0.value > 1 }.keys)
    }

    /// The same wiring with these channels only.
    public func restricted(to channels: [Int]) -> ChannelWiring {
        ChannelWiring(ports: ports.filter { channels.contains($0.key) })
    }

    // Written as an object keyed by the channel number ("3": [...]): readable, and stable.
    private enum CodingKeys: String, CodingKey { case ports }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self).decode([String: [String]].self, forKey: .ports)
        ports = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: ports.map { (String($0.key), $0.value) }), forKey: .ports)
    }
}

/// What a direction gets the first time: its channels go to the first ports of the sound card, in order.
public enum DefaultWiring {
    public static func make(channels: [Int], systemPorts: [String]) -> ChannelWiring {
        var w = ChannelWiring()
        for (i, channel) in channels.enumerated() where systemPorts.indices.contains(i) { w.ports[channel] = [systemPorts[i]] }
        return w
    }
}

extension ChannelWiring {
    /// The wiring that some links make for a program: the links that end on `in_N` of the client (the sender) or start at `out_N` of it (the receiver), for the
    /// channels N that the program has. Links of other ports are not the program's.
    public init(links: Set<JackLink>, direction: LinkDirection, client: String, channels: [Int]) {
        var ports: [Int: [String]] = [:]
        let word = direction == .send ? "in" : "out"
        for channel in channels {
            let own = "\(client):\(word)_\(channel)"
            let others = links.compactMap { link -> String? in
                if direction == .send { return link.input == own ? link.output : nil }
                return link.output == own ? link.input : nil
            }
            if !others.isEmpty { ports[channel] = others.sorted() }
        }
        self.init(ports: ports)
    }
}

/// How the connections that are really in JACK differ from the wiring of the matrix. The matrix shows what the person wants; JACK can hold something else
/// because another tool (a patchbay, JackMate) made or removed a connection.
public struct WiringDifferences: Equatable, Sendable {
    /// In the wiring, not in JACK, although both ports are there: the connection was removed elsewhere.
    public var missing = ChannelWiring.empty
    /// In JACK on a port of the program, not in the wiring: the connection was made elsewhere.
    public var foreign = ChannelWiring.empty
    public static let none = WiringDifferences()
    public init(missing: ChannelWiring = .empty, foreign: ChannelWiring = .empty) { self.missing = missing; self.foreign = foreign }
    public var isEmpty: Bool { missing.ports.isEmpty && foreign.ports.isEmpty }
    public var missingCount: Int { missing.ports.values.reduce(0) { $0 + $1.count } }
    public var foreignCount: Int { foreign.ports.values.reduce(0) { $0 + $1.count } }

    /// - Parameters:
    ///   - actual: what the graph holds for the ports of the program.
    ///   - bothPortsExist: whether the port of the program and the other one are in the graph. A connection that is not made because a port is not there (a device
    ///     that is unplugged, an application that is not running) is not a difference: it is made when the port comes.
    public init(wiring: ChannelWiring, actual: ChannelWiring, channels: [Int], bothPortsExist: (_ channel: Int, _ port: String) -> Bool) {
        var missing = ChannelWiring(), foreign = ChannelWiring()
        for channel in channels {
            let wanted = Set(wiring.ports[channel] ?? []), real = Set(actual.ports[channel] ?? [])
            for port in wanted.subtracting(real).sorted() where bothPortsExist(channel, port) { missing.toggle(channel: channel, port: port) }
            for port in real.subtracting(wanted).sorted() { foreign.toggle(channel: channel, port: port) }
        }
        self.init(missing: missing, foreign: foreign)
    }
}

/// Keeps the connections of the ports of one program as the wiring says: it turns the wiring of the channels into the links
/// that are wanted, and the reconciler of JackBridge makes them as far as the graph allows (see `ConnectionReconciler`).
@MainActor
public final class WiringManager {
    public let direction: LinkDirection
    public private(set) var wiring = ChannelWiring.empty
    /// The JACK client of the program, once it runs.
    public private(set) var clientName: String?
    /// The channels of the program: its ports are `in_N` or `out_N` for these N.
    public private(set) var channels: [Int] = []
    /// Ports of the other clients that the wiring names and that are not in the graph.
    public var missingPorts: Set<String> { reconciler.missingPorts }
    /// Connections that JACK refused for another reason than a missing port.
    public var failures: [String] { reconciler.failures }

    private let reconciler: ConnectionReconciler
    private let linking: JackLinking
    /// What the graph holds that the wiring does not say, and the reverse; read again by `refreshReality`.
    public private(set) var differences = WiringDifferences.none

    public init(direction: LinkDirection, linking: JackLinking) {
        self.direction = direction
        self.linking = linking
        // The sender's inputs are fed by other clients; the receiver's outputs feed other clients.
        reconciler = ConnectionReconciler(linking: linking, own: direction == .send ? .input : .output)
    }

    /// The port of a channel on the program.
    public func port(channel: Int, client: String) -> String { "\(client):\(direction == .send ? "in" : "out")_\(channel)" }

    /// The program runs: its ports exist, or will in a moment. The wiring is made as far as possible.
    public func attach(client: String, channels: [Int], wiring: ChannelWiring) {
        clientName = client
        self.channels = channels
        self.wiring = wiring
        reconciler.reset()
        reconcile()
    }

    /// The person used the matrix: connects what is new and disconnects what is gone.
    public func update(wiring: ChannelWiring) {
        self.wiring = wiring
        reconcile()
    }

    /// The graph has changed (a port has appeared): connects what was missing.
    public func graphChanged() {
        guard clientName != nil else { return }
        reconcile()
    }

    /// The program has ended: its connections go with it.
    public func detach() {
        clientName = nil
        reconciler.reset()
        differences = .none
    }

    /// Reads the connections of the program in the graph, and compares them with the wiring. Only while the program runs: the wiring of a program that does not
    /// run is prepared in advance, and there is nothing to compare it with.
    @discardableResult
    public func refreshReality() -> WiringDifferences {
        guard let client = clientName else { differences = .none; return .none }
        let actual = ChannelWiring(links: reconciler.actualLinks(ownClient: client), direction: direction, client: client, channels: channels)
        let outputs = linking.outputPorts(), inputs = linking.inputPorts()
        let sends = direction == .send
        let result = WiringDifferences(wiring: wiring, actual: actual, channels: channels) { channel, other in
            let own = self.port(channel: channel, client: client)
            return sends ? inputs.contains(own) && outputs.contains(other) : outputs.contains(own) && inputs.contains(other)
        }
        differences = result
        return result
    }

    private func reconcile() {
        guard let client = clientName else { return }
        var wanted = Set<JackLink>()
        for channel in channels {
            let own = port(channel: channel, client: client)
            for other in wiring.ports[channel] ?? [] {
                wanted.insert(direction == .send ? JackLink(output: other, input: own) : JackLink(output: own, input: other))
            }
        }
        reconciler.reconcile(wanted: wanted)
    }
}

/// The wiring of each direction, kept between launches.
public final class WiringStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ direction: LinkDirection) -> String { "wiring.\(direction.rawValue)" }

    /// What is remembered for a direction, or nil the first time.
    public func wiring(for direction: LinkDirection) -> ChannelWiring? {
        defaults.data(forKey: key(direction)).flatMap { try? JSONDecoder().decode(ChannelWiring.self, from: $0) }
    }

    public func remember(_ wiring: ChannelWiring, for direction: LinkDirection) {
        if let data = try? JSONEncoder().encode(wiring) { defaults.set(data, forKey: key(direction)) }
    }
}
