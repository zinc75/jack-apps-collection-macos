// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge

/// What the connections of a running engine become when someone else changes them: **the reality is adopted**. A connection made elsewhere (JackMate, a
/// patchbay) is wanted from now on, one removed elsewhere is no longer wanted, and a connection whose other port is not in the graph (an application that is
/// not running, a device that is unplugged) keeps its place and is made when the port comes.
public enum WiringAdoption {
    /// - Parameters:
    ///   - wanted: the connections the wiring asks for now.
    ///   - links: the connections that are in the graph (all of them).
    ///   - ownClient: the JACK client of the engine: only the connections of its ports count.
    ///   - outputs, inputs: the audio ports that are in the graph.
    public static func adopted(wanted: Set<JackLink>, links: Set<JackLink>, ownClient: String, outputs: Set<String>, inputs: Set<String>) -> Set<JackLink> {
        let prefix = ownClient + ":"
        let actual = links.filter { $0.output.hasPrefix(prefix) || $0.input.hasPrefix(prefix) }
        var result = actual
        for link in wanted where !actual.contains(link) && !(outputs.contains(link.output) && inputs.contains(link.input)) { result.insert(link) }
        return result
    }

    /// The ports of a channel: the ones that stay keep their order, the new ones follow by name.
    public static func ordered(_ current: [String], _ now: Set<String>) -> [String] {
        current.filter(now.contains) + now.subtracting(current).sorted()
    }
}
