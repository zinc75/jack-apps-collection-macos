// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import JConvolverKit
import SwiftUI

extension AppModel {
    /// The name of the JACK client of jconvolver: the one of the file, or the program's own.
    var ownClientName: String { document?.content.client ?? "jconvolver" }

    /// The full name of a port of jconvolver.
    func ownPort(_ side: PortSide, _ index: Int) -> String {
        "\(ownClientName):\(document?.portName(side, index) ?? "")"
    }

    /// The connections the configuration asks for: the ports that each channel has in the file.
    var wantedLinks: Set<JackLink> {
        guard let document else { return [] }
        var links = Set<JackLink>()
        for i in 0..<document.inputCount { for c in document.connections(.input, i) { links.insert(JackLink(output: c, input: ownPort(.input, i))) } }
        for o in 0..<document.outputCount { for c in document.connections(.output, o) { links.insert(JackLink(output: ownPort(.output, o), input: c)) } }
        return links
    }

    /// What a click on a crossing of the matrix does: the channel goes to this port, or leaves it.
    func toggleWire(_ side: PortSide, channel: Int, port: String) {
        edit(String(localized: "branchement")) { $0.toggleConnection(port, side, channel) }
    }

    func clearWires(_ side: PortSide) {
        edit(String(localized: "effacement des branchements")) { $0.clearConnections(side) }
    }

    func wireToSoundCard(_ side: PortSide) {
        let ports = side == .input ? jack.capturePorts : jack.playbackPorts
        edit(String(localized: "retour à la carte son")) { $0.connectToSoundCard(side, ports: ports) }
    }

    /// While the program runs, a change of a connection is made at once (and the same on undo): the connections that are no
    /// longer wanted are taken away, the new ones are made.
    func syncConnections() {
        guard mode == .realTime, controller.isRunning else { appliedLinks = []; return }
        let wanted = wantedLinks
        for link in appliedLinks.subtracting(wanted) { jack.disconnect(from: link.output, to: link.input) }
        for link in wanted.subtracting(appliedLinks) { jack.connect(from: link.output, to: link.input) }
        appliedLinks = wanted
    }

    /// The channels of a side that are connected to nothing, from 1.
    func unconnected(_ side: PortSide) -> [Int] { (document?.unconnectedChannels(side) ?? []).map { $0 + 1 } }

    /// A dot on the connections while a channel is connected to nothing.
    var connectionsNeedAttention: Bool {
        isOpen && mode == .realTime && (!unconnected(.input).isEmpty || !unconnected(.output).isEmpty)
    }
}
