// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// What is wrong with the chosen sources, seen from the JACK graph as it is now: channels that nothing
/// feeds, ports whose client is gone, input ports that nothing is connected to. Each of them gives a
/// silent channel in the file.
public struct SourceCheck: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The port is not in the graph (its client is not running).
        case absent
        /// An input port that nothing is connected to: it carries no signal.
        case nothingConnected
    }

    public struct Problem: Equatable, Sendable {
        /// From 1, as shown to the user.
        public let channel: Int
        public let port: String
        public let kind: Kind
    }

    /// Channels (from 1) with no source, while others have one.
    public private(set) var unassigned: [Int] = []
    public private(set) var problems: [Problem] = []

    public var isClean: Bool { unassigned.isEmpty && problems.isEmpty }

    public init() {}

    /// `available` holds every output and input port ("client:port") of the graph. Nothing is checked
    /// when the connections are left to the patchbay. With no source chosen at all nothing would be connected:
    /// every channel is reported.
    public init(sources: [[String]], channels: Int, autoConnect: Bool, available: Set<String>, inputConnections: [String: [String]]) {
        let assignment = SourceAssignment(sources, channels: channels)
        guard autoConnect else { return }
        for (index, ports) in assignment.perChannel.enumerated() {
            if ports.isEmpty { unassigned.append(index + 1); continue }
            for port in ports {
                if !available.contains(port) {
                    problems.append(Problem(channel: index + 1, port: port, kind: .absent))
                } else if inputConnections[port]?.isEmpty == true {
                    problems.append(Problem(channel: index + 1, port: port, kind: .nothingConnected))
                }
            }
        }
    }

    /// One sentence per kind of problem, for the warning and for the configuration.
    public var descriptions: [String] {
        var lines: [String] = []
        if !unassigned.isEmpty {
            // "Channel 3 has no source", never a bare number that reads as a count.
            let list = ListFormatter.localizedString(byJoining: unassigned.map(String.init))
            lines.append(unassigned.count == 1 ? String(localized: "La voie \(list) n'a pas de source.")
                                               : String(localized: "Les voies \(list) n'ont pas de source."))
        }
        for problem in problems {
            switch problem.kind {
            case .absent: lines.append(String(localized: "Source absente : \(problem.port) (voie \(problem.channel))."))
            case .nothingConnected: lines.append(String(localized: "Rien n'est relié à \(problem.port) (voie \(problem.channel))."))
            }
        }
        return lines
    }
}
