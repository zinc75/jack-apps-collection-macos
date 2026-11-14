// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import Foundation

/// An input port of the JACK server, and whether the output of Klick is connected to it.
public struct JackPort: Equatable, Identifiable, Sendable {
    /// "client:port".
    public let name: String
    /// A port of the hardware.
    public let isPhysical: Bool
    public let isConnected: Bool

    public var id: String { name }

    public init(name: String, isPhysical: Bool, isConnected: Bool) {
        self.name = name
        self.isPhysical = isPhysical
        self.isConnected = isConnected
    }

    /// The client the port belongs to: what comes before the first colon.
    public var client: String {
        name.firstIndex(of: ":").map { String(name[..<$0]) } ?? name
    }

    /// The port without its client: what comes after the first colon.
    public var shortName: String {
        name.firstIndex(of: ":").map { String(name[name.index(after: $0)...]) } ?? name
    }

    /// The list of `klick_jack_list_ports`: one port per line, `p` or `-` (hardware), `1` or `0` (connected), a tab between the fields.
    public static func parse(_ text: String) -> [JackPort] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, !fields[2].isEmpty else { return nil }
            return JackPort(name: String(fields[2]), isPhysical: fields[0] == "p", isConnected: fields[1] == "1")
        }
    }
}

/// The ports of one client, for the list of the connections.
public struct JackClientPorts: Identifiable, Equatable, Sendable {
    public let name: String
    public let ports: [JackPort]

    public var id: String { name }
    /// A client of the hardware (the first of the list).
    public var isPhysical: Bool { ports.contains { $0.isPhysical } }

    /// The ports grouped by client, in the order of the server, the clients of the hardware first.
    public static func grouped(_ ports: [JackPort]) -> [JackClientPorts] {
        var order: [String] = []
        var byClient: [String: [JackPort]] = [:]
        for port in ports {
            if byClient[port.client] == nil { order.append(port.client) }
            byClient[port.client, default: []].append(port)
        }
        let groups = order.map { JackClientPorts(name: $0, ports: byClient[$0] ?? []) }
        return groups.filter(\.isPhysical) + groups.filter { !$0.isPhysical }
    }
}
