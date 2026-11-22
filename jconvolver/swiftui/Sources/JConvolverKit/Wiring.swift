// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The inputs of jconvolver, or its outputs.
public enum PortSide: Sendable {
    case input, output
}

/// The JACK connections of the ports of jconvolver. A line of the configuration file gives a port the ports to connect it to:
/// the first is what every version of jconvolver connects, the others what a jconvolver with the 0004 patch of this
/// repository connects (the other versions ignore them).
extension ConvDocument {
    private func specs(_ side: PortSide) -> [ConvPortSpec] { side == .input ? content.inputs : content.outputs }
    private func spec(_ side: PortSide, _ index: Int) -> ConvPortSpec? {
        let all = specs(side)
        return all.indices.contains(index) ? all[index] : nil
    }

    /// The name of the port of a channel on the program: the one of the file, or the one jconvolver gives (`in-3`, `out-3`).
    public func portName(_ side: PortSide, _ index: Int) -> String {
        spec(side, index)?.name ?? "\(side == .input ? "in" : "out")-\(index + 1)"
    }

    /// The ports of other clients that a channel is connected to, as `client:port`, in the order of the file.
    public func connections(_ side: PortSide, _ index: Int) -> [String] {
        spec(side, index)?.connections ?? []
    }

    /// Replaces the ports a channel is connected to (the same port twice counts once).
    public mutating func setConnections(_ ports: [String], _ side: PortSide, _ index: Int) {
        var seen = Set<String>()
        let list = ports.filter { !$0.isEmpty && seen.insert($0).inserted }
        switch side {
        case .input where content.inputs.indices.contains(index): content.inputs[index].connections = list
        case .output where content.outputs.indices.contains(index): content.outputs[index].connections = list
        default: break
        }
    }

    /// What a click on a crossing does: connects the channel to the port, or disconnects it if it already is.
    public mutating func toggleConnection(_ port: String, _ side: PortSide, _ index: Int) {
        var list = connections(side, index)
        if let i = list.firstIndex(of: port) { list.remove(at: i) } else { list.append(port) }
        setConnections(list, side, index)
    }

    /// Disconnects every channel of a side.
    public mutating func clearConnections(_ side: PortSide) {
        for i in 0..<(side == .input ? content.inputs.count : content.outputs.count) { setConnections([], side, i) }
    }

    /// Connects channel k to the k-th port of the sound card, in order, and to nothing else; the channels beyond the ports
    /// are disconnected.
    public mutating func connectToSoundCard(_ side: PortSide, ports: [String]) {
        for i in 0..<(side == .input ? content.inputs.count : content.outputs.count) {
            setConnections(ports.indices.contains(i) ? [ports[i]] : [], side, i)
        }
    }

    /// The channels (from 0) that are connected to nothing: an input stays silent, an output goes nowhere.
    public func unconnectedChannels(_ side: PortSide) -> [Int] {
        specs(side).indices.filter { specs(side)[$0].connections.isEmpty }
    }

    /// The ports that take more than one output: JACK adds their signals.
    public var summedDestinations: Set<String> {
        var count = [String: Int]()
        for spec in content.outputs { for c in Set(spec.connections) { count[c, default: 0] += 1 } }
        return Set(count.filter { $0.value > 1 }.keys)
    }

    /// The inputs that are fed by more than one port: JACK adds their signals too (from 0).
    public var mixedInputs: [Int] {
        content.inputs.indices.filter { content.inputs[$0].connections.count > 1 }
    }
}
