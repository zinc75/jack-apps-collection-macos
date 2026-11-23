// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge

/// Keeps the connections of the ports of `jack_play` as the routing says. The ports of a program that has just been
/// started appear a moment after it, and the destinations may be applications that are not running yet: what cannot
/// be connected now is kept, and made when the port appears. The connections themselves are made by the reconciler of
/// JackBridge, shared with the other tools; this turns the routing of the channels into the links that are wanted.
@MainActor
public final class ConnectionManager {
    public private(set) var routing = ChannelRouting.empty(channels: 0)
    public private(set) var clientName: String?
    /// Destinations of the routing that are not in the graph.
    public var missingPorts: Set<String> { reconciler.missingPorts }
    /// Connections that JACK refused for another reason than a missing port.
    public var failures: [String] { reconciler.failures }

    private let reconciler: ConnectionReconciler

    /// The application attaches the manager once the program has said its ports exist, so they are not checked.
    public init(linking: JackLinking) { reconciler = ConnectionReconciler(linking: linking, own: .output, checksOwnPorts: false) }

    /// The output port of a channel (from 0) of the player.
    public static func output(client: String, channel: Int) -> String { "\(client):out_\(channel + 1)" }

    /// Starts keeping the connections of the player `client`: its ports exist, the routing is made as far as possible.
    public func attach(client: String, routing: ChannelRouting) {
        clientName = client
        self.routing = routing
        reconciler.reset()
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
        reconciler.reset()
    }

    private func reconcile() {
        guard let client = clientName else { return }
        reconciler.reconcile(wanted: wantedLinks(client: client))
    }

    private func wantedLinks(client: String) -> Set<JackLink> {
        var wanted = Set<JackLink>()
        for (channel, ports) in routing.channels.enumerated() {
            for port in ports { wanted.insert(JackLink(output: Self.output(client: client, channel: channel), input: port)) }
        }
        return wanted
    }

    /// The routing as the graph really has it, when it is not the one that was asked for: **the reality is adopted**. A connection made elsewhere (JackMate,
    /// a patchbay) is part of the routing from now on, one removed elsewhere is no longer in it; a destination that is not in the graph keeps its place and
    /// is connected when it comes. nil when the graph is as the routing says.
    public func adoptedRouting() -> ChannelRouting? {
        guard let client = clientName else { return nil }
        let wanted = wantedLinks(client: client)
        let adopted = reconciler.adopted(wanted: wanted, ownClient: client)
        guard adopted != wanted else { return nil }
        var channels = routing.channels
        for c in channels.indices {
            let output = Self.output(client: client, channel: c)
            // The ports that stay keep their order; the new ones follow by name.
            let kept = channels[c].filter { adopted.contains(JackLink(output: output, input: $0)) }
            let added = adopted.filter { $0.output == output && !kept.contains($0.input) }.map(\.input).sorted()
            channels[c] = kept + added
        }
        return ChannelRouting(channels: channels)
    }
}
