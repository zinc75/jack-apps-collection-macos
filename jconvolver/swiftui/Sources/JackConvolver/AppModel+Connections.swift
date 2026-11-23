// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import JConvolverKit
import SwiftUI

extension AppModel {
    /// The name of the JACK client of jconvolver: the one of the file, or the program's own.
    var ownClientName: String {
        if controller.isRunning, mode == .realTime, let runClientName { return runClientName }
        return document?.content.client ?? "jconvolver"
    }

    /// The name of the JACK client of this session's engine while it runs, nil otherwise: an engine that is not running has no client, and a client that has
    /// the name of the file is then another engine's.
    var runningClientName: String? {
        controller.isRunning && mode == .realTime ? runClientName : nil
    }

    /// The full name of a port of jconvolver.
    func ownPort(_ side: PortSide, _ index: Int) -> String {
        "\(ownClientName):\(document?.portName(side, index) ?? "")"
    }

    /// What the page of the connections shows and changes: the connections as they are in JACK while the engine runs, else those of the file.
    var wiringSource: ConvDocument? { liveWiring ?? document }

    /// The connections the configuration asks for: the ports that each channel has in the file (while the engine runs, those that were made since).
    var wantedLinks: Set<JackLink> {
        guard let document = wiringSource else { return [] }
        var links = Set<JackLink>()
        for i in 0..<document.inputCount { for c in document.connections(.input, i) { links.insert(JackLink(output: c, input: ownPort(.input, i))) } }
        for o in 0..<document.outputCount { for c in document.connections(.output, o) { links.insert(JackLink(output: ownPort(.output, o), input: c)) } }
        return links
    }

    /// What a click on a crossing of the matrix does: the channel goes to this port, or leaves it.
    func toggleWire(_ side: PortSide, channel: Int, port: String) {
        changeWiring(String(localized: "branchement")) { $0.toggleConnection(port, side, channel) }
    }

    func clearWires(_ side: PortSide) {
        changeWiring(String(localized: "effacement des branchements")) { $0.clearConnections(side) }
    }

    func wireToSoundCard(_ side: PortSide) {
        let ports = side == .input ? jack.capturePorts : jack.playbackPorts
        changeWiring(String(localized: "retour à la carte son")) { $0.connectToSoundCard(side, ports: ports) }
    }

    /// A change of the connections. While the engine runs in real time it is an action in JACK only (made at once): the file is not touched, and
    /// when the engine stops the person is asked whether to write what was made. Otherwise it is an edit of the configuration, as any.
    private func changeWiring(_ label: String, _ change: (inout ConvDocument) -> Void) {
        if isLocked, mode == .realTime, var live = liveWiring {
            change(&live)
            guard live != liveWiring else { return }
            liveWiring = live
            syncConnections()
        } else {
            edit(label, change)
        }
    }

    /// The engine started or stopped. When it stops, the connections made meanwhile are offered to the file if they are not those it had.
    func engineRunningChanged() {
        guard !controller.isRunning, let live = liveWiring else { return }
        liveWiring = nil
        guard let document, mode == .realTime else { return }
        func wiring(_ d: ConvDocument) -> [[Set<String>]] {
            [(0..<d.inputCount).map { Set(d.connections(.input, $0)) }, (0..<d.outputCount).map { Set(d.connections(.output, $0)) }]
        }
        if wiring(live) != wiring(document) {
            pendingWiring = live
            showsApplyWiring = true
        }
    }

    /// Writes the connections made while the engine ran into the configuration (one step of the history).
    func applyPendingWiring() {
        guard let live = pendingWiring else { return }
        pendingWiring = nil
        edit(String(localized: "branchements faits pendant l'exécution")) { d in
            for i in 0..<min(d.inputCount, live.inputCount) { d.setConnections(live.connections(.input, i), .input, i) }
            for o in 0..<min(d.outputCount, live.outputCount) { d.setConnections(live.connections(.output, o), .output, o) }
        }
    }

    func discardPendingWiring() { pendingWiring = nil }

    /// While the program runs, a change of a connection is made at once (and the same on undo): the connections that are no
    /// longer wanted are taken away, the new ones are made.
    func syncConnections() {
        guard mode == .realTime, controller.isRunning else { appliedLinks = []; return }
        // Nothing is connected while the name of the client is not known: it could be the name of another engine.
        guard runClientName != nil else { return }
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
