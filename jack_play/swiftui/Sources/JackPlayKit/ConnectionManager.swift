// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the connection manager needs from the JACK server. The real one is `PlaybackGraph`; the tests give a fake.
@MainActor
public protocol JackLinking: AnyObject {
    /// The audio input ports of the graph now, as `"client:port"`.
    func inputPorts() -> Set<String>
    /// The ports an output is connected to now.
    func destinations(of output: String) -> Set<String>
    func connect(from output: String, to input: String) throws
    func disconnect(from output: String, to input: String) throws
}

/// Keeps the connections of the ports of `jack_play` as the routing says. The ports of a program that has just been
/// started appear a moment after it, and the destinations may be applications that are not running yet: what cannot
/// be connected now is kept, and made when the port appears.
@MainActor
public final class ConnectionManager {
    /// A connection, from an output of the player to an input port.
    struct Link: Hashable {
        let output: String
        let input: String
    }

    public private(set) var routing = ChannelRouting.empty(channels: 0)
    public private(set) var clientName: String?
    /// Destinations of the routing that are not in the graph.
    public private(set) var missingPorts: Set<String> = []
    /// Connections that JACK refused for another reason than a missing port.
    public private(set) var failures: [String] = []

    private let linking: JackLinking
    private var applied: Set<Link> = []

    public init(linking: JackLinking) { self.linking = linking }

    /// The output port of a channel (from 0) of the player.
    public static func output(client: String, channel: Int) -> String { "\(client):out_\(channel + 1)" }

    /// Starts keeping the connections of the player `client`: its ports exist, the routing is made as far as possible.
    public func attach(client: String, routing: ChannelRouting) {
        clientName = client
        self.routing = routing
        applied = []
        reconcile()
    }

    /// The routing has changed (the person used the matrix): connects what is new and disconnects what is gone.
    public func update(routing: ChannelRouting) {
        self.routing = routing
        reconcile()
    }

    /// The graph has changed (a port has appeared): connects the destinations that were missing.
    public func graphChanged() {
        guard clientName != nil else { return }
        reconcile()
    }

    /// The player has ended: its connections go with it.
    public func detach() {
        clientName = nil
        applied = []
        missingPorts = []
        failures = []
    }

    private func reconcile() {
        guard let client = clientName else { return }
        let inputs = linking.inputPorts()
        var wanted = Set<Link>()
        for (channel, ports) in routing.channels.enumerated() {
            for port in ports { wanted.insert(Link(output: Self.output(client: client, channel: channel), input: port)) }
        }
        // What is gone from the routing.
        for link in applied.subtracting(wanted) {
            try? linking.disconnect(from: link.output, to: link.input)
            applied.remove(link)
        }
        var missing = Set<String>(), failed = [String]()
        for link in wanted {
            guard inputs.contains(link.input) else { missing.insert(link.input); continue }
            if applied.contains(link) { continue }
            if linking.destinations(of: link.output).contains(link.input) {
                applied.insert(link)   // already made (by a previous run of the same player, or by another tool)
                continue
            }
            do {
                try linking.connect(from: link.output, to: link.input)
                applied.insert(link)
            } catch {
                failed.append("\(link.output) → \(link.input)")
            }
        }
        // A connection that was made and is gone because its destination left is made again when it returns.
        applied = applied.filter { inputs.contains($0.input) }
        missingPorts = missing
        failures = failed
    }
}
